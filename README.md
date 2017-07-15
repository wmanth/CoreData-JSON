# CoreData-JSON

CoreData-JSON is an extension to the Apple Core Data classes `NSManagedObject` and `NSManagedObjectContext` to import and export data of a managed object context from and to JSON data.

To get the JSON representation of a managed object simply call 'jsonObject'.

The JSON representation of a managed object looks like
```json
{
    "entity" : "Employee",
    "id" : "AB9F1A3D-C12B-4A78-9BE6-059A9BA6C983",
    "attributes" : {
        "name" : "Bob",
        "since" : "2016-08-01T09:00:00-04:00"
    },
    "relations" : {
        "department" : "5B9F0B71-6CAF-4D15-B295-254F6C013050"
    }
}
```

The entire managed object context can be exported to json by calling `jsonData`. To import a JSON data into a managed object context use `importJSONData`

## Examples
### Swift
```
self.managedObjectContext.importJSONData(jsonData)
```
### Objective-C
```
[self.managedObjectContext importJSONData:jsonData]
```
