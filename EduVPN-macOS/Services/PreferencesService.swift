//
//  PreferencesService.swift
//  eduVPN
//
//  Created by Johan Kool on 10/08/2017.
//  Copyright © 2017-2019 Commons Conservancy.
//

import Cocoa
import ServiceManagement

class PreferencesService: NSObject {
    
    static let shared = PreferencesService()
    
    override init() {
        launchAtLogin = PreferencesService.launchAtLogin(bundle: PreferencesService.loginHelperBundle)
        UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: "launchAtLogin", options: .new, context: nil)
    }
    
    var launchAtLogin: Bool {
        didSet {
            setLaunchAtLogin(bundle: PreferencesService.loginHelperBundle, enabled: launchAtLogin)
        }
    }
    
    private static var loginHelperBundle: Bundle {
        let mainBundle = Bundle.main
        let bundlePath = (mainBundle.bundlePath as NSString).appendingPathComponent("Contents/Library/LoginItems/LoginItemHelper-macOS.app")
        return Bundle(path: bundlePath)! //swiftlint:disable:this force_unwrapping
    }
    
    private static func launchAtLogin(bundle: Bundle) -> Bool {
        // From the docs regarding deprecation:
        // For the specific use of testing the state of a login item that may have been
        // enabled with SMLoginItemSetEnabled() in order to show that state to the
        // user, this function remains the recommended API. A replacement API for this
        // specific use will be provided before this function is removed.
        guard let dictionaries = SMCopyAllJobDictionaries(kSMDomainUserLaunchd).takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        return dictionaries.first(where: { $0["Label"] as? String == bundle.bundleIdentifier }) != nil
    }
    
    private func setLaunchAtLogin(bundle: Bundle, enabled: Bool) {
        let status = LSRegisterURL(bundle.bundleURL as CFURL, true)
        if status != noErr {
            NSLog("LSRegisterURL failed to register \(bundle.bundleURL) [\(status)]")
        }
        
        if !SMLoginItemSetEnabled(bundle.bundleIdentifier! as CFString, enabled) { //swiftlint:disable:this force_unwrapping
            NSLog("SMLoginItemSetEnabled failed!")
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        
        updateForUIPreferences()
    }
    
    func updateForUIPreferences() {
        let launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        
        self.launchAtLogin = launchAtLogin
    }
}
