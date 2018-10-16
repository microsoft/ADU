# ADU - Analytics Platform System Appliance Diagnostic Utility with Wellness Checks

### Usage

**You can download the newest releast from the 'release' page.** Extract the downloaded file (ADU-_version_.zip) to HST01 under C:\. The name of the ADU folder is not important unless you have set up automated jobs that depend on a particular folder structure. By default it will look like this: C:\ADU-4.5\ADU.ps1

Execute it using PowerShell: C:\ADU-4.5\ADU.ps1

A menu will be displayed to select your options. All of these are safe to run while the appliance is online, but as a best practice you should not be making changes to the appliance under the highest volume times due to possible performance impact on the appliance or diagnostic tool. 



## Functionality

* **PRE-RELEASE: INSTALL_WINDOWS_UPDATES**: install windows updates that have been downloaded through WSUS, but do not reboot. THis can be performed online. This feature has been tested on AU5 and is still in pre-release form. Contact Nicksalc for help using it pre-release form.

* **Diagnostics Collection**: Collect logs and diagnostic data from appliance
* **Distributed command**: Run a command on all nodes or a subset of nodes.
* **Check WMI Leak**: Checks that WMI has not had any leaks and fixes it if required (online)
* **Fix Network Connection Profile**: Checks for adapters on the wrong profile and attempts to repair it (onlin)
* **Get Network adapter Config**: Retrieves the IP configuration from all network adapters in the appliance
* **Manage Performance Counters**: Turn performance counters on or off on all nodes of the appliance. 
* **Publish PDW XMLs**: Copy one set of XMLs out to the rest of the servers. 
* **Set External Time Source**: Will ask for an NTP server and attempt to set the appliance to sync to that source
* **All Table Sizes**: Collects size and rowcount for all tables in selected database (or all)
* **Audit SQL Security Logs**:
* **Backup Test**:
* **Database Space Report**: Retrieves used and unused database space including the specified space when DB was created.
* **Distributed Table Sizes**: Collects size of all distributed tables in selected database (or all)
* **Failed Data Loads**:
* **Generate CSV from XMLS (Beta)**:
* **Last Modified Statistics**: Collects the last modified date for all statistics on all tables in the specified database (or all)
* **Orphaned Table Listing**: Checks all databases for orphaned tables
* **Replicated Table Sizes**: Collects size of all replicated tables. Generally to make sure none are too large.
* **Replicated vs Distributed space by filegroup**: Collects the space usage by filegroup
* **Run PAV**: Runs Appliance Validator
* **Table Info**:
* **Table Skew**: Collects table skew for all tables in specified database (or all)
* **Add Canpool Disks to storage pool**: Adds any disks that are not part of the storage pool to the storage pool
* **Align Disks**: Aligns CSVs to their proper owners for best performance
* **Data Volume Utilization**: Returns space usage from the volume level
* **Remove Lost Communication Disks**: Removes any metadata leftover form removed disks
* **Storage Health Check**: Runs a health check against the storage subsystem. Results in HTML
* **Update Storage Cache**: Updates storage cache on all physical servers
* **Wellness Checks**: A gui will come up so you can choose what tests you want. Details below. 

## Wellness Checks
Wellness checks will open a gui where you can select the tests you would like to run. The output will be in HTML format, but some of it is best copied into excel for in depth review of the results.

* **Run PAV**: Run Appliance Validator from HST01
* **Analyze PAV Results**: Analyze PAV results and put them in a readable format
* **Active Alerts**: Collect any current active PDW alerts
* **PDW Password Expiry**: Check for windows users passwords expiring in the next 7 days
* **C Drive Free Space**: Checks that all servers/VMs have adequate free space
* **D Drive Free Space**: Checks that all servers/VMs have adequate free space
* **WMI Health**: Checks that WMI has not had any leaks
* **Replicated Table Sizes**: Checks for large replicated tables
* **Statistics Accuracy**: Checks the accuracy of existing statistics
* **CCI Health**: Checks the health of Clustered Columnstore Indexes
* **Unhealthy Physical Disks**: Checks for physical disks in unhealhty state
* **Retired Physical Disks**: Checks for physical disks that have been retired
* **Disks with Canpool True**: Checks for physical disks that are not in the storage pool
* **Unhealthy Virtual Disks**: Checks for unhealthy virtual disks
* **CSV's Online**: Checks that all CSV's are online
* **Unhealthy Storage Pools**: Checks that storage pools are healthy
* **Number Physical Disks in Virtual Disks**: Checks that every virtual disk has 2 physical disks
* **Physical Disk Reliability Counters**: Checks if reliability counters indicate an iminent disk failure
* **Orphaned Tables**: Checks for orphaned tables in any database
* **Data Skew**: Checks that data skew is below a set threshold for all tables all databases
* **Network Adapter Profile**: Checks that network adapters are all on the domain profile.
* **Time Sync Configuration**: Checks that the appliance is syncing to an NTP server
* **Nullable Distribution Columns**: Checks for any nullable distribution columns
