//
//  Instance+CoreDataProperties.swift
//  EduVPN
//
//  Created by Jeroen Leenarts on 04-02-18.
//  Copyright © 2018 SURFNet. All rights reserved.
//
//

import Foundation
import CoreData

extension Instance {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Instance> {
        return NSFetchRequest<Instance>(entityName: "Instance")
    }

    @NSManaged public var providerType: String?
    @NSManaged public var baseUri: String?
    @NSManaged public var publicKey: String?
    @NSManaged public var apis: NSSet?
    @NSManaged public var displayNames: NSSet?
    @NSManaged public var logos: NSSet?

}

// MARK: Generated accessors for apis
extension Instance {

    @objc(addApisObject:)
    @NSManaged public func addToApis(_ value: Api)

    @objc(removeApisObject:)
    @NSManaged public func removeFromApis(_ value: Api)

    @objc(addApis:)
    @NSManaged public func addToApis(_ values: NSSet)

    @objc(removeApis:)
    @NSManaged public func removeFromApis(_ values: NSSet)

}

// MARK: Generated accessors for displayNames
extension Instance {

    @objc(addDisplayNamesObject:)
    @NSManaged public func addToDisplayNames(_ value: DisplayName)

    @objc(removeDisplayNamesObject:)
    @NSManaged public func removeFromDisplayNames(_ value: DisplayName)

    @objc(addDisplayNames:)
    @NSManaged public func addToDisplayNames(_ values: NSSet)

    @objc(removeDisplayNames:)
    @NSManaged public func removeFromDisplayNames(_ values: NSSet)

}

// MARK: Generated accessors for logos
extension Instance {

    @objc(addLogosObject:)
    @NSManaged public func addToLogos(_ value: Logo)

    @objc(removeLogosObject:)
    @NSManaged public func removeFromLogos(_ value: Logo)

    @objc(addLogos:)
    @NSManaged public func addToLogos(_ values: NSSet)

    @objc(removeLogos:)
    @NSManaged public func removeFromLogos(_ values: NSSet)

}
