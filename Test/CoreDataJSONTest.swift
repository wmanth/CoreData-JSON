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

import XCTest
import CoreData

class CoreDataJSONTest: XCTestCase
{
    let testBundle = Bundle(for: CoreDataJSONTest.self)

    lazy var managedObjectModel: NSManagedObjectModel = {
        let modelURL = self.testBundle.url(forResource: "TestModel", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()

    lazy var storeCoordinator: NSPersistentStoreCoordinator = {
        let storeCoordianator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        do {
            try storeCoordianator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        } catch {
            fatalError("Error adding persistent store to coordinator.")
        }
        return storeCoordianator
    }()

    lazy var managedObjectContext: NSManagedObjectContext = {
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = self.storeCoordinator
        return managedObjectContext
    }()

    override func setUp()
    {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown()
    {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }


    func testImportEmpty() throws
    {
        self.managedObjectContext.importJSONData("[]".data(using: .utf8)!)
    }

    func testImportData() throws
    {
        let testDataUrl = self.testBundle.url(forResource: "TestData", withExtension: "json")
        let testData = try Data(contentsOf:testDataUrl!)

        self.managedObjectContext.importJSONData(testData)

        let companies = try self.managedObjectContext.fetch(Company.fetchRequest()) as [Company]
        XCTAssert(companies.count == 1)

        let departments = try self.managedObjectContext.fetch(Department.fetchRequest()) as [Department]
        XCTAssert(departments.count == 2)

        let employees = try self.managedObjectContext.fetch(Employee.fetchRequest()) as [Employee]
        XCTAssert(employees.count == 6)

        let company = companies.first!
        XCTAssert(company.title == "Company Name")

        for dept in departments { XCTAssert(dept.company == company) }

        let dept1 = company.departments?.firstObject as! Department
        let dept2 = company.departments?.lastObject as! Department
        XCTAssert(dept1.label == "D1")
        XCTAssert(dept2.label == "D2")
    }

    func testExportJSONObject() throws
    {
        let employee = NSEntityDescription.insertNewObject(forEntityName: "Employee", into: self.managedObjectContext) as! Employee
        employee.name = "Bob"
        employee.since = NSDate()

        let jsonObject = employee.jsonObject() as NSDictionary
        XCTAssert(jsonObject.value(forKeyPath: "entity") as? String == employee.entity.name)
        XCTAssert(jsonObject.value(forKeyPath: "attributes.name") as? String == employee.name)

        let sinceDate = ISO8601DateFormatter().date(from: jsonObject.value(forKeyPath: "attributes.since") as! String)
        XCTAssert(Int((sinceDate?.timeIntervalSinceReferenceDate)!) == Int((employee.since?.timeIntervalSinceReferenceDate)!))
    }

    func testExportJSONData() throws
    {
        let testDataUrl = self.testBundle.url(forResource: "TestData", withExtension: "json")
        let testData = try Data(contentsOf:testDataUrl!)

        self.managedObjectContext.importJSONData(testData)

        let data = self.managedObjectContext.jsonData()
        XCTAssert(data != nil)
        let string = String.init(data: data!, encoding: .utf8)
        XCTAssert(string != nil)
        print(string!)
    }
}
