//
//  ApiService.swift
//  eduVPN
//
//  Created by Jeroen Leenarts on 02-08-17.
//  Copyright © 2017 SURFNet. All rights reserved.
//

import Foundation

import Moya

import PromiseKit
import AppAuth

import os.log

enum ApiServiceError: Swift.Error {
    case noAuthState
    case unauthorized
    case urlCreationFailed
    case tokenRefreshFailed(rootCause: Error)

    var localizedDescription: String {
        switch self {
        case .noAuthState:
            return NSLocalizedString("No stored auth state.", comment: "")
        case .unauthorized:
            return NSLocalizedString("You are not authorized.", comment: "")
        case .urlCreationFailed:
            return NSLocalizedString("URL creation failed.", comment: "")
        case .tokenRefreshFailed(let rootCause):
            return String(format: NSLocalizedString("Token refresh failed due to %@", comment: ""), rootCause.localizedDescription)
        }
    }
}

enum ApiService {
    case profileList
    case userInfo
    case createKeypair(displayName: String)
    case checkCertificate(commonName: String)
    case profileConfig(profileId: String)
    case systemMessages
}

extension ApiService {
    var path: String {
        switch self {
        case .profileList:
            return "/profile_list"
        case .userInfo:
            return "/user_info"
        case .createKeypair:
            return "/create_keypair"
        case .checkCertificate:
            return "/check_certificate"
        case .profileConfig:
            return "/profile_config"
        case .systemMessages:
            return "/system_messages"
        }
    }

    var method: Moya.Method {
        switch self {
        case .profileList, .userInfo, .profileConfig, .systemMessages, .checkCertificate:
            return .get
        case .createKeypair:
            return .post
        }
    }

    var task: Task {
        switch self {
        case .profileList, .userInfo, .systemMessages:
            return .requestPlain
        case .createKeypair(let displayName):
            return .requestParameters(parameters: ["display_name": displayName], encoding: URLEncoding.httpBody)
        case .checkCertificate(let commonName):
            return .requestParameters(parameters: ["common_name": commonName], encoding: URLEncoding.queryString)
        case .profileConfig(let profileId):
            return .requestParameters(parameters: ["profile_id": profileId], encoding: URLEncoding.queryString)
        }
    }

    var sampleData: Data {
        return "".data(using: String.Encoding.utf8) ?? Data()
    }
}

struct DynamicApiService: TargetType, AcceptJson {
    let baseURL: URL
    let apiService: ApiService

    var path: String { return apiService.path }
    var method: Moya.Method { return apiService.method }
    var task: Task { return apiService.task }
    var sampleData: Data { return apiService.sampleData }
}

class DynamicApiProvider: MoyaProvider<DynamicApiService> {
    let api: Api
    let authConfig: OIDServiceConfiguration
    private var credentialStorePlugin: CredentialStorePlugin

    var actualApi: Api {
        return api.instance?.group?.distributedAuthorizationApi ?? api
    }

    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    public func authorize(presentingViewController: UIViewController) -> Promise<OIDAuthState?> {
        let request = OIDAuthorizationRequest(configuration: authConfig, clientId: Config.shared.clientId, scopes: ["config"], redirectURL: Config.shared.redirectUrl, responseType: OIDResponseTypeCode, additionalParameters: nil)
        return Promise(resolver: { seal in
            currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: presentingViewController, callback: { (authState, error) in

                if let error = error {
                    seal.reject(error)
                    return
                }

                self.actualApi.authState = authState

                precondition(authState != nil, "THIS SHOULD NEVER HAPPEN")

                self.api.managedObjectContext?.performAndWait {
                    self.api.instance?.group?.distributedAuthorizationApi = self.actualApi
                }
                do {
                    try self.api.managedObjectContext?.save()
                } catch {
                    seal.reject(error)
                    return
                }

                seal.fulfill(authState)
            })
        })
    }

    public init?(api: Api, endpointClosure: @escaping EndpointClosure = MoyaProvider.defaultEndpointMapping,
                 stubClosure: @escaping StubClosure = MoyaProvider.neverStub,
                 callbackQueue: DispatchQueue? = nil,
                 manager: Manager = MoyaProvider<Target>.ephemeralAlamofireManager(),
                 plugins: [PluginType] = [],
                 trackInflights: Bool = false) {
//    public init(api: Api, endpointClosure: @escaping EndpointClosure = MoyaProvider.defaultEndpointMapping,
//                requestClosure: @escaping RequestClosure = MoyaProvider.defaultRequestMapping,
//                stubClosure: @escaping StubClosure = MoyaProvider.neverStub,
//                manager: Manager = MoyaProvider<DynamicInstanceService>.defaultAlamofireManager(),
//                plugins: [PluginType] = [],
//                trackInflights: Bool = false) {
        guard let authorizationEndpoint = api.authorizationEndpoint else { return nil }
        guard let authorizationEndpointURL = URL(string: authorizationEndpoint) else { return nil }

        guard let tokenEndpoint = api.tokenEndpoint else { return nil }
        guard let tokenEndpointURL = URL(string: tokenEndpoint) else { return nil }
        self.api = api
        self.credentialStorePlugin = CredentialStorePlugin()

        var plugins = plugins
        plugins.append(self.credentialStorePlugin)

        self.authConfig = OIDServiceConfiguration(authorizationEndpoint: authorizationEndpointURL, tokenEndpoint: tokenEndpointURL)
        super.init(endpointClosure: endpointClosure, stubClosure: stubClosure, manager: manager, plugins: plugins, trackInflights: trackInflights)

    }

    public func request(apiService: ApiService,
                        queue: DispatchQueue? = nil,
                        progress: Moya.ProgressBlock? = nil) -> Promise<Moya.Response> {
        return Promise<Void>(resolver: { seal in
            if let authState = self.actualApi.authState {
                authState.performAction(freshTokens: { (accessToken, _, error) in
                    if let error = error {
                        if (error as NSError).code == OIDErrorCode.networkError.rawValue {
                            seal.reject(error)
                        } else {
                            os_log("Token refresh failed.", log: Log.auth, type: .error)
                            seal.reject(ApiServiceError.tokenRefreshFailed(rootCause: error))
                        }
                        return
                    }

                    self.credentialStorePlugin.accessToken = accessToken
                    seal.fulfill(())
                })
            } else {
                os_log("No auth state.", log: Log.auth, type: .error)
                seal.reject(ApiServiceError.noAuthState)
            }

        }).then {_ -> Promise<Moya.Response> in
            guard let apiBaseUri = self.api.apiBaseUri, let baseURL = URL(string: apiBaseUri) else {
                throw ApiServiceError.urlCreationFailed
            }
            return self.request(target: DynamicApiService(baseURL: baseURL, apiService: apiService))
        }.then({ response throws -> Promise<Moya.Response> in
                if response.statusCode == 401 {
                    throw ApiServiceError.unauthorized
                }

                return Promise.value(response)
            })
    }
}

extension DynamicApiProvider: Hashable {
    static func == (lhs: DynamicApiProvider, rhs: DynamicApiProvider) -> Bool {
        return lhs.api.apiBaseUri == rhs.api.apiBaseUri
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(api.apiBaseUri)
    }
}
