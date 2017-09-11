/*
 Copyright (c) 2017, Wolfram Manthey
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 The views and conclusions contained in the software and documentation are those
 of the authors and should not be interpreted as representing official policies,
 either expressed or implied, of the FreeBSD Project.
*/

#import "CoreData+JSON.h"

#import <CommonCrypto/CommonDigest.h>


static NSString * const JSONEntityNameKey       = @"entity";
static NSString * const JSONEntityIdKey         = @"id";
static NSString * const JSONEntityAttributesKey = @"attributes";
static NSString * const JSONEntityRelationsKey  = @"relations";

#pragma mark JSONDateTransformer

@interface _JSONDateTransformer : NSValueTransformer
@end

@implementation _JSONDateTransformer

+ (Class)transformedValueClass { return NSDate.class; }
+ (BOOL)allowsReverseTransformation { return YES; }

+ (NSDateFormatter *)rfc3339DateFormatter
{
    static NSDateFormatter *rfc3339DateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rfc3339DateFormatter = [NSDateFormatter new];
        rfc3339DateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        rfc3339DateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        rfc3339DateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    return rfc3339DateFormatter;
}

- (id)transformedValue:(id)value
{
    NSAssert([value isKindOfClass:NSString.class], @"Object to be transformed not of kind NSString: %@", value);
    return [self.class.rfc3339DateFormatter dateFromString:value];
}

- (id)reverseTransformedValue:(id)value
{
    NSAssert([value isKindOfClass:NSDate.class], @"Object to be transformed not of kind NSDate: %@", value);
    return [self.class.rfc3339DateFormatter stringFromDate:value];
}

@end

#pragma mark - JSONDataTransformer

@interface _JSONDataTransformer : NSValueTransformer
@end

@implementation _JSONDataTransformer

+ (Class)transformedValueClass { return NSData.class; }
+ (BOOL)allowsReverseTransformation { return YES; }

- (id)transformedValue:(id)value
{
    NSAssert([value isKindOfClass:NSString.class], @"Object to be transformed not of kind NSString: %@", value);
    return nil;
}

- (id)reverseTransformedValue:(id)value
{
    NSAssert([value isKindOfClass:NSData.class], @"Object to be transformed not of kind NSData: %@", value);
    return nil;
}

@end

#pragma mark - NSAttributeDescription

@interface NSAttributeDescription (JSON)
@property (readonly, nullable) NSValueTransformer *valueTransformer;
@end

@implementation NSAttributeDescription (JSON)

- (NSValueTransformer *)valueTransformer
{
    switch (self.attributeType)
    {
        case NSDateAttributeType:       return [_JSONDateTransformer new];
        case NSBinaryDataAttributeType: return [_JSONDataTransformer new];
        default: return nil;
    }
}

@end

#pragma mark - NSManagedObject

@implementation NSManagedObject (JSON)

- (NSManagedObject *)initWithJSONAttributes:(NSDictionary *)attributes
                                     entity:(NSEntityDescription *)entity
             insertIntoManagedObjectContext:(NSManagedObjectContext *)context
{
    if (self = [self initWithEntity:entity insertIntoManagedObjectContext:context])
    {
        // enumerate all attributes and set their values according to the JSON data
        [entity.attributesByName enumerateKeysAndObjectsUsingBlock:^(NSString *attributeName,
                                                                     NSAttributeDescription *attributeDescription,
                                                                     BOOL *stop)
         {
             // do nothing if the attribute is not set in JSON dictionary
             if (!attributes[attributeName]) return;

             // select a transformer to transform the JSON attribute into the managed object attribute
             NSValueTransformer *transformer = attributeDescription.valueTransformer;

             // copy the (transformed) JSON attribute into the managed object
             [self setPrimitiveValue:transformer ? [transformer transformedValue:attributes[attributeName]] : attributes[attributeName]
                              forKey:attributeName];
         }];
    }
    return self;
}

- (void)finalizeWithJSONRelations:(NSDictionary *)relations objectMapping:(NSDictionary *)objectMapping
{
    // enumerate all attributes and set their values according to the JSON data
    [self.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString *relationshipName,
                                                                         NSRelationshipDescription *relationshipDescription,
                                                                         BOOL *stop)
     {
         id jsonRelations = relations[relationshipDescription.name];

         // do nothing if the relationship is not set in JSON dictionary
         if (!jsonRelations) return;

         if (relationshipDescription.toMany)
         {
             NSAssert([jsonRelations isKindOfClass:NSArray.class], @"Relation '%@' is a to-many relationship", relationshipName);
             NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[jsonRelations count]];
             for (NSString *jsonRelation in jsonRelations)
             {
                 NSManagedObject *object = objectMapping[jsonRelation];
                 NSAssert(object, @"Object for relation '%@' %@ not found!", relationshipName, jsonRelation);
                 if (object) [objects addObject:object];
             }
             id set = relationshipDescription.ordered ? [NSOrderedSet orderedSetWithArray:objects] : [NSSet setWithArray:objects];
             [self setPrimitiveValue:set forKey:relationshipName];
         }
         else
         {
             NSAssert([jsonRelations isKindOfClass:NSString.class], @"Relation '%@' is a to-one relationship", relationshipName);
             NSManagedObject *object = objectMapping[jsonRelations];
             [self setPrimitiveValue:object forKey:relationshipName];
         }
     }];
}

- (NSUUID *)objectUUID
{
    NSString* uri = self.objectID.URIRepresentation.absoluteString;

    // calculate the MD5 checksum from the absolute object ID uri string
    uint8_t md5[CC_MD5_DIGEST_LENGTH];
    CC_MD5(uri.UTF8String, (CC_LONG)uri.length, md5);

    // create a UUID from the MD5 checksum as they have the same length
    return [[NSUUID alloc] initWithUUIDBytes:md5];
}

- (NSDictionary *)jsonObject
{
    NSMutableDictionary *attributes    = [NSMutableDictionary dictionaryWithCapacity:self.entity.attributesByName.count];
    NSMutableDictionary *relationships = [NSMutableDictionary dictionaryWithCapacity:self.entity.relationshipsByName.count];

    // iterate through the attributes and add their values to the JSON object
    [self.entity.attributesByName enumerateKeysAndObjectsUsingBlock:^(NSString *attributeName,
                                                                      NSAttributeDescription *attributeDescription,
                                                                      BOOL *stop)
     {
         // get the attribute value
         id attribute = [self primitiveValueForKey:attributeName];

         // do nothing if the attribute is not set
         if (!attribute) return;

         // select a transformer to transform the JSON attribute into the managed object attribute
         NSValueTransformer *transformer = attributeDescription.valueTransformer;
         attributes[attributeName] = transformer ? [transformer reverseTransformedValue:attribute] : attribute;
     }];

    // iterate through the relationships and add their values to the JSON object
    [self.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString *relationshipName,
                                                                         NSRelationshipDescription *relationshipDescription,
                                                                         BOOL *stop)
     {
         // get the relationship object(s)
         id relationship = [self primitiveValueForKey:relationshipName];

         if (relationshipDescription.toMany)
         {
             NSArray *relationObjects = relationshipDescription.ordered ? [relationship array] : [relationship allObjects];
             NSMutableArray *relations = [NSMutableArray arrayWithCapacity:relationObjects.count];
             for (NSManagedObject *relationObject in relationObjects)
             {
                 [relations addObject:relationObject.objectUUID.UUIDString];
             }
             // set the JSON value to an array of the relationship objects UUIDs
             relationships[relationshipName] = [NSArray arrayWithArray:relations];
         }
         else
         {
             // set the JSON value to the relationship objects UUID
             relationships[relationshipName] = [[relationship objectUUID] UUIDString];
         }
     }];

    NSMutableDictionary *jsonObject = [NSMutableDictionary dictionary];

    jsonObject[JSONEntityNameKey] = self.entity.name;
    jsonObject[JSONEntityIdKey] = self.objectUUID.UUIDString;
    jsonObject[JSONEntityAttributesKey] = attributes;
    jsonObject[JSONEntityRelationsKey] = relationships;
    
    return jsonObject;
}

@end

#pragma mark - NSManagedObjectContext

@implementation NSManagedObjectContext (JSON)

- (void)importJSONData:(NSData *)jsonData
{
    NSError *error;
    NSArray *jsonObjects = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];

    // if parsing the JSON data fails return nil
    NSAssert(!error, @"JSON data could not be parsed successfully!");
    if (error) return;

    NSMutableDictionary<NSString *, NSManagedObject *> *objectDict = [[NSMutableDictionary alloc] initWithCapacity:jsonObjects.count];
    NSMutableDictionary<NSString *, NSDictionary *>  *relationDict = [[NSMutableDictionary alloc] initWithCapacity:jsonObjects.count];

    // iterate through all JSON objects to create managed objects
    for (NSDictionary *jsonObject in jsonObjects)
    {
        NSString *objectId = jsonObject[JSONEntityIdKey];

        // create an entity description according to the name of the entity in JSON
        NSEntityDescription *entityDescription = [NSEntityDescription entityForName:jsonObject[JSONEntityNameKey]
                                                             inManagedObjectContext:self];

        objectDict[objectId] = [[NSManagedObject alloc] initWithJSONAttributes:jsonObject[JSONEntityAttributesKey]
                                                                         entity:entityDescription
                                                 insertIntoManagedObjectContext:self];

        relationDict[objectId] = jsonObject[JSONEntityRelationsKey];
    }

    // restore all relationships
    [relationDict enumerateKeysAndObjectsUsingBlock:^(NSString *objectId, NSDictionary *relations, BOOL *stop)
    {
        NSManagedObject *object = objectDict[objectId];
        [object finalizeWithJSONRelations:relationDict[objectId] objectMapping:objectDict];
    }];
}

- (NSData * _Nullable)exportPersistentStore
{
    // first fetch all entities to register their objects in the context
    for (NSEntityDescription *entity in self.persistentStoreCoordinator.managedObjectModel.entities)
    {
        NSError *error = nil;
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entity.name];
        [self executeFetchRequest:fetchRequest error:&error];
        NSAssert(!error, @"Could not fetch objects of entity '%@'", entity.name);
    }

    return self.jsonData;
}

- (NSData * _Nullable)jsonData
{
    NSMutableArray *jsonObject = [NSMutableArray arrayWithCapacity:self.registeredObjects.count];

    for (NSManagedObject *object in self.registeredObjects)
    {
        [jsonObject addObject:[object jsonObject]];
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    return jsonData;
}

@end
