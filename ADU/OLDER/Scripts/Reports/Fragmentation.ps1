#Get Fragmentation
#AU3 - don't have to pass PDWDomain
#pdwquery is query in ExecutePdwQuery

param([string]$username,[string]$password,[string]$database,[string]$table)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

$distributionCount=""#number of distributions
$username="sa"
$password="dogmat1C"
$PDWDomain="PSSC8A"
$serverinstance = "10.200.181.207,17001"

#get the list of DBs
$DBListQuery = "select a.database_id, a.name, b.physical_name from sys.databases as a, sys.pdw_database_mappings as b where a.database_id = b.database_id and a.name NOT IN ('master','tempdb')"
$DBList = ExecutePdwQuery -PdwQuery $DBListQuery -U $username -P $password -PDWDomain $PDWDomain

#create the initial menu array
$TableMenuOptions=@()
$TableMenuOptions = (
	@{"header"="Run for All Databases"},
	"All DBs",
	@{"header"="Select a single database"}
)

#Add the DB names to the array
for ($i=1;$i -le $DBList.count; $i++) {$TableMenuOptions+=($DBList[$i-1].name)}

#ask user what DB
[string]$ans = OutputMenu -header "Please Select a Database" -options $TableMenuOptions
if($ans -eq "q"){break}

if ($ans -eq "All DBs")
{
	#leave $DBList.name
}
else{$database=$ans}

#run code depending if the user selected a specific database or all
if($database)
{
	$db = $DBList | ? {$_.name -eq "$database"}

	#could ask about a particular table here
	#use the database and get the table list
	$tableinfoQuery = "use $database;SELECT DISTINCT name, tab.[object_id], physical_name FROM sys.tables tab JOIN sys.pdw_table_mappings ptm ON tab.object_id = ptm.object_id"
	$tableInfo = ExecutePdwQuery -PdwQuery $tableinfoQuery -U $username -P $password -PDWDomain $PDWDomain


	foreach($tableObject in $tableInfo)
	{
        $TotalFrag=0
		write-host "$($tableObject.name) $($tableObject.Physical_name)"
		$fragQuery = "select avg(avg_fragmentation_in_percent) as AverageFrag from sys.dm_db_index_physical_stats (DB_ID(N'${$Db.physical_name}'),OBJECT_ID(N'${$tableObject.object_id}'),NULL,NULL,'LIMITED') GROUP BY object_id"
		$fragResults = ExecuteSqlQuery -node "PSSC8A-CMP01" -query $fragQuery 
		$fragResults
		
		$fragResults | ? {$_.AverageFrag -ne 0} | ft -AutoSize
        
        foreach ($result in $fragResults.averageFrag)
        {
            $totalFrag+=$result
        }
       $TotalFrag
       Write-host "Average Fragmentation: " ($TotalFrag/64)
	}
}
else
{
}