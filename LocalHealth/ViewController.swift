//
//  ViewController.swift
//  LocalHealth
//
//  Created by Russell Ladd on 10/18/15.
//  Copyright © 2015 GRL5. All rights reserved.
//

import UIKit
import CloudKit
import MultipeerConnectivity
import CoreMotion

class ViewController: UICollectionViewController, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    
    required init?(coder aDecoder: NSCoder) {
        
        container = CKContainer.defaultContainer()
        
        database = container.privateCloudDatabase
        
        if !NSUserDefaults.standardUserDefaults().boolForKey("subscribed") {
            
            let subscriptoion = CKSubscription(recordType: "Number", predicate: NSPredicate(format: "TRUEPREDICATE"), options: [.FiresOnRecordCreation])
            
            let info = CKNotificationInfo()
            info.shouldSendContentAvailable = true
            subscriptoion.notificationInfo = info
            
            database.saveSubscription(subscriptoion) { (subscription, error) -> Void in
                
                if error == nil {
                    NSUserDefaults.standardUserDefaults().setBool(true, forKey: "subscribed")
                    print("Subscription saved!")
                }
            }
        }
        
        if let data = NSUserDefaults.standardUserDefaults().dataForKey("peerID") {
            
            peer = NSKeyedUnarchiver.unarchiveObjectWithData(data) as! MCPeerID
            
        } else {
            
            peer = MCPeerID(displayName: NSUUID().UUIDString)
            
            let data = NSKeyedArchiver.archivedDataWithRootObject(peer)
            NSUserDefaults.standardUserDefaults().setObject(data, forKey: "peerID")
        }
        
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: "grl5-locket")
        
        browser = MCNearbyServiceBrowser(peer: peer, serviceType: "grl5-locket")
        
        session = MCSession(peer: peer)
        
        super.init(coder: aDecoder)
        
        loadDatesByRecordID()
        
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        browser.delegate = self
        browser.startBrowsingForPeers()
        
        session.delegate = self
    }
    
    // MARK: CloudKit
    
    let container: CKContainer
    let database: CKDatabase
    
    // MARK: MultipeerConnectivity
    
    let peer: MCPeerID
    
    let advertiser: MCNearbyServiceAdvertiser
    let browser: MCNearbyServiceBrowser
    
    let session: MCSession
    
    func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
        
        invitationHandler(true, session)
    }
    
    func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        
        browser.invitePeer(peerID, toSession: session, withContext: nil, timeout: 0.0)
    }
    
    func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        
    }
    
    var connectedPeers = [MCPeerID]()
    
    func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        
        NSOperationQueue.mainQueue().addOperationWithBlock {
            
            if state == .Connected {
                
                self.connectedPeers.append(peerID)
                
                self.fetchAllRecords()
                
            } else {
                
                if let index = self.connectedPeers.indexOf(peerID) {
                    self.connectedPeers.removeAtIndex(index)
                }
            }
        }
    }
    
    func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        
        NSOperationQueue.mainQueue().addOperationWithBlock {
            
            let message = NSKeyedUnarchiver.unarchiveObjectWithData(data) as! [String: NSData]
            
            print("Received message")
            
            if let recordIDsData = message["recordIDs"] {
                
                print("Received request")
                
                let recordIDs = NSKeyedUnarchiver.unarchiveObjectWithData(recordIDsData) as! [CKRecordID]
                
                var datesByRecordID = [CKRecordID: Walk]()
                
                for recordID in recordIDs {
                    
                    // Don't know if you're allowed to set nil - could be a point of failure
                    datesByRecordID[recordID] = self.datesByRecordID[recordID]
                }
                
                let datesByRecordIDData = NSKeyedArchiver.archivedDataWithRootObject(datesByRecordID)
                
                let responseMessage = ["datesByRecordID": datesByRecordIDData]
                
                let responseMessageData = NSKeyedArchiver.archivedDataWithRootObject(responseMessage)
                
                try! session.sendData(responseMessageData, toPeers: [peerID], withMode: .Reliable)
            }
            
            if let datesByRecordIDData = message["datesByRecordID"] {
                
                print("Received response")
                
                let datesByRecordID = NSKeyedUnarchiver.unarchiveObjectWithData(datesByRecordIDData) as! [CKRecordID: Walk]
                
                for (recordID, date) in datesByRecordID {
                    
                    self.datesByRecordID[recordID] = date
                }
                
                self.saveDatesByRecordID()
            }
        }
    }
    
    func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {
        
    }
    
    func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
        
    }
    
    // MARK: Pedometer
    
    let pedometer = CMPedometer()
    
    // MARK: Model
    
    class Walk: NSObject, NSCoding {
        
        init(numberOfSteps: Int, startDate: NSDate) {
            
            self.numberOfSteps = numberOfSteps
            self.startDate = startDate
            
            super.init()
        }
        
        required init?(coder aDecoder: NSCoder) {
            
            numberOfSteps = aDecoder.decodeIntegerForKey("numberOfSteps")
            startDate = aDecoder.decodeObjectForKey("startDate") as! NSDate
            
            super.init()
        }
        
        func encodeWithCoder(aCoder: NSCoder) {
            
            aCoder.encodeInteger(numberOfSteps, forKey: "numberOfSteps")
            aCoder.encodeObject(startDate, forKey: "startDate")
        }
        
        let numberOfSteps: Int
        let startDate: NSDate
    }
    
    var datesByRecordID = [CKRecordID: Walk]() {
        didSet {
            
            dates = datesByRecordID.values.sort({ (date1, date2) -> Bool in
                
                if date1.startDate.compare(date2.startDate) == .OrderedSame {
                    return date1.numberOfSteps < date2.numberOfSteps
                }
                
                return date1.startDate.compare(date2.startDate) == .OrderedAscending
            })
        }
    }
    
    var dates = [Walk]() {
        didSet {
            if isViewLoaded() {
                collectionView!.reloadData()
            }
        }
    }
    
    func saveDatesByRecordID() {
        
        let data =  NSKeyedArchiver.archivedDataWithRootObject(datesByRecordID)
        
        NSUserDefaults.standardUserDefaults().setObject(data, forKey: "datesByRecordID")
    }
    
    func loadDatesByRecordID() {
        
        if let data = NSUserDefaults.standardUserDefaults().objectForKey("datesByRecordID") as? NSData {
            
            datesByRecordID = NSKeyedUnarchiver.unarchiveObjectWithData(data) as! [CKRecordID: Walk]
        }
    }
    
    var allRecords = [CKRecord]()
    
    func missingRecordIDsForPeer(peer: MCPeerID) -> [CKRecordID] {
        
        return allRecords.filter { record in
            
            let peerName = record.objectForKey("peer") as? String ?? ""
            
            return datesByRecordID[record.recordID] == nil && peerName == peer.displayName
            
        }.map { $0.recordID }
    }
    
    func fetchAllRecords() {
        
        let query = CKQuery(recordType: "Number", predicate: NSPredicate(format: "TRUEPREDICATE"))
        
        self.database.performQuery(query, inZoneWithID: nil) { records, error in
            
            NSOperationQueue.mainQueue().addOperationWithBlock {
                
                if let records = records {
                    
                    self.allRecords = records
                    
                    print("Fetched \(records.count) records")
                    
                    self.requestMissingData()
                }
            }
        }
    }
    
    func requestMissingData() {
        
        for peer in connectedPeers {
            
            let recordIDsToFetch = missingRecordIDsForPeer(peer)
            
            if !recordIDsToFetch.isEmpty {
                
                let recordIDsData = NSKeyedArchiver.archivedDataWithRootObject(recordIDsToFetch)
                
                let message = ["recordIDs": recordIDsData]
                
                let messageData = NSKeyedArchiver.archivedDataWithRootObject(message)
                
                print("Message sent")
                
                try! session.sendData(messageData, toPeers: [peer], withMode: .Reliable)
            }
        }
    }
    
    // MARK: View
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pedometer.startPedometerUpdatesFromDate(NSDate()) { (data, error) -> Void in
            
            if let data = data {
                
                self.addNumberWithData(Walk(numberOfSteps: data.numberOfSteps.integerValue, startDate: NSDate()))
            }
        }
    }
    
    func addNumberWithData(walk: Walk) {
        
        let record = CKRecord(recordType: "Number")
        record.setObject(peer.displayName, forKey: "peer")
        
        database.saveRecord(record) { record, error in
            
            NSOperationQueue.mainQueue().addOperationWithBlock {
                
                if let record = record {
                    
                    self.datesByRecordID[record.recordID] = walk
                    
                    self.saveDatesByRecordID()
                }
            }
        }
    }
    
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dates.count
    }
    
    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier("Walk Cell", forIndexPath: indexPath) as! WalkCell
        
        cell.label.text = dates[indexPath.row].numberOfSteps.description
        
        return cell
    }
}

class WalkCell: UICollectionViewCell {
    
    @IBOutlet weak var label: UILabel!
}
