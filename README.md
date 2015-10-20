# Locket
*Developed at BoilerMake 2015*

As phones add health monitoring capabilites to their features, the question of how to manage the growing heap of personal and private data is paramount.

Health data sync is noticeably absent in iOS- regulations make storing it on the cloud complicated, whether there are any real risks or not.

Locket is a service that uses the new iOS multipeer communication framework to securely share data between your devices, without the data ever touching the cloud.

We developed a network filesystem that is centrally managed with CloudKit, but syncs using direct, secure peer-to-peer communication. The result: reliable sharing with complete peace of mind.



## Security 

#### Authentication
Locket uses iCloud for authentication. Apple uses strong multifactor authentication when joining a device to an iCloud account-  Locket works seamlessly with all devices under the same account. 

#### Confidentiality
File metadata is stored in iCloud, but the data exists only on your devices- it is transferred point-to-point using the magic of asymmetric cryptography. 

#### Availability
The central CloudKit database keeps track of file changes and synchronization. If your device needs files, it is informed by the cloud controller, and will sync as soon as another device is within proximity. 

#### Integrity
The CloudKit controller is exclusive to your account and accessible only via authenticated devices. The multipeer API uses iCloud trust to establish secure sessions with each peer-to-peer transfer. 
