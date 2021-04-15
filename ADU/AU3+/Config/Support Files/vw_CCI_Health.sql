CREATE VIEW [dbo].[vw_CCI_Health] AS 

WITH 
	cteTables AS (
		SELECT DISTINCT RunID, RunDateTime, DBName, TableName
			FROM CCI_Health
			WHERE RunID IN (SELECT MAX(RunID) as RunID 
								FROM CCI_Health
								WHERE NodeName IS NOT NULL
								GROUP BY DBName)
			 AND  TableName != ''),						-- Eliminates Orphaned Tables
	cteOpen AS (
		SELECT 	c.RunID, c.DBName, c.TableName,
				SUM(c.RG_Count)		AS Open_RG_Count,
				SUM(c.TotalRows)	AS Open_TotalRows, 
				SUM(c.TotalRows) / SUM(c.RG_Count) 
									AS Open_AvgRows_per_RG
			FROM CCI_Health c
				INNER JOIN cteTables t
					ON  c.RunID = t.RunID
					AND c.DBName = t.DBName
					AND c.TableName = t.TableName
			WHERE c.RG_State = 1
			GROUP BY c.RunID, c.DBName, c.TableName),
	cteClosed AS (
		SELECT 	c.RunID, c.DBName, c.TableName,
				SUM(c.RG_Count)		AS Closed_RG_Count,
				SUM(c.TotalRows)	AS Closed_TotalRows, 
				SUM(c.TotalRows) / SUM(c.RG_Count) 
									AS Closed_AvgRows_per_RG
			FROM CCI_Health c
				INNER JOIN cteTables t
					ON  c.RunID = t.RunID
					AND c.DBName = t.DBName
					AND c.TableName = t.TableName			
			WHERE c.RG_State = 2
			GROUP BY c.RunID, c.DBName, c.TableName),
	cteCompressed AS (
		SELECT 	c.RunID, c.DBName, c.TableName,
				SUM(c.RG_Count)			AS Compressed_RG_Count,
				SUM(c.TotalRows)		AS Compressed_TotalRows, 
				MIN(c.MinRows)			AS Compressed_MinRows_per_RG,
				MAX(c.MaxRows)			AS Compressed_MaxRows_per_RG,
				SUM(c.TotalRows) / SUM(c.RG_Count) 
										AS Compressed_AvgRows_per_RG,
				SUM(DeletedRows)		AS Compressed_DeletedRows,
				CAST((100 * ( SUM(CAST(DeletedRows AS DECIMAL(15,4))) / SUM(CAST(TotalRows AS DECIMAL(15,4))) ) ) AS DECIMAL(9,4)) 
										AS Compressed_AvgFragPct,
				MIN(FragmentationPct)	AS Compressed_MinFragPct,
				MAX(FragmentationPct)	AS Compressed_MaxFragPct
			FROM CCI_Health c
				INNER JOIN cteTables t
					ON  c.RunID = t.RunID
					AND c.DBName = t.DBName
					AND c.TableName = t.TableName			
			WHERE c.RG_State = 3
			GROUP BY c.RunID, c.DBName, c.TableName)

SELECT	t.RunDateTime AS CheckDateTime,
		t.DBName, 
		t.TableName,
		o.Open_RG_Count,
		o.Open_TotalRows, 
		o.Open_AvgRows_per_RG,
		c.Closed_RG_Count,
		c.Closed_TotalRows, 
		c.Closed_AvgRows_per_RG,
		x.Compressed_RG_Count,
		x.Compressed_TotalRows, 
		x.Compressed_MinRows_per_RG,
		x.Compressed_MaxRows_per_RG,
		x.Compressed_AvgRows_per_RG,
		x.Compressed_DeletedRows,
		x.Compressed_AvgFragPct,
		x.Compressed_MinFragPct,
		x.Compressed_MaxFragPct
	FROM cteTables t
		LEFT OUTER JOIN cteOpen o
			ON  t.RunID = o.RunID
			AND t.DBName = o.DBName
			AND t.TableName = o.TableName
		LEFT OUTER JOIN cteClosed c
			ON  t.RunID = c.RunID
			AND t.DBName = c.DBName
			AND t.TableName = c.TableName
		LEFT OUTER JOIN cteCompressed x
			ON  t.RunID = x.RunID
			AND t.DBName = x.DBName
			AND t.TableName = x.TableName;
GO
