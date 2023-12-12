\set QUIET 1
\echo <!DOCTYPE html>
\echo <html><meta charset="utf-8" />
\echo <style>
\echo #finditem,table {box-shadow: 0px 20px 30px -10px grey; margin: 2em; caption {font:large bold; text-align:left; span {font: italic bold 1.7em Georgia, serif}}}
\echo table, th, td { border: 1px solid black; border-collapse: collapse; padding: 2px 4px 2px 4px;} 
\echo th {background-color: #d2f2ff;cursor: pointer; }
\echo tr:nth-child(even) {background-color: #eef8ff} 
\echo a:hover,tr:hover { background-color: #EBFFDA}
\echo /* h2 { scroll-margin-left: 2em;} keep the scroll left
\echo caption { font-size: larger } */
\echo ol { width: fit-content;}
\echo .warn { font-weight:bold; background-color: #FBA }
\echo .high { border: 5px solid red;font-weight:bold}
\echo .lime { font-weight:bold;background-color: #FFD}
\echo .lineblk {float: left; margin:2em }
\echo .thidden tr { td:nth-child(2),th:nth-child(2) {display: none} td:first-child {color:blue}}
\echo #bottommenu { position: fixed; right: 0px; bottom: 0px; padding: 5px; border : 2px solid #AFAFFF; border-radius: 5px;}
\echo #cur { font: 5em arial; position: absolute; color:brown; animation: vanish 0.8s ease forwards; }  /*sort indicator*/
\echo #dtls,#finditem,#menu {position: absolute;background-color:#FAFFEA;border: 2px solid blue; border-radius: 5px; padding: 1em;box-shadow: 0px 20px 30px -10px grey}
\echo @keyframes vanish { from { opacity: 1;} to {opacity: 0;} }
\echo summary {  padding: 1rem; font: bold 1.2em arial;  cursor: pointer } 
\echo footer { text-align: center; padding: 3px; background-color:#d2f2ff}
\echo </style>
\H
\pset footer off 
SET max_parallel_workers_per_gather = 0;

\echo <h1>
\echo   <svg width="10em" viewBox="0 0 140 80">
\echo     <path fill="none" stroke="#000000" stroke-linecap="round" stroke-width="2"  d="m 21.2,46.7 c 1,2 0.67,4 -0.3,5.1 c -1.1,1 -2,1.5 -4,1 c -10,-3 -4,-25 -4 -25 c 0.6,-10 8,-9 8 -9 s 7,-4.5 11,0.2 c 1.2,1.4 1.7,3.3 1.7,5.17 c -0.1,3 3,7 -2,10 c-2,2 -1,5 -8,5.5 m -2 -12 c 0,0 -1,1 -0.2,0.2 m -4 12 c 0,0 0,10 -12,11"/>
\echo     <text x="30" y="50" style="font:25px arial">gGather</text>
\echo     <text x="60" y="62" style="fill:red; font:15px arial">Report</text>
\echo    </svg>
\echo    <b id="busy" class="warn"> Loading... </b>
\echo </h1>
\pset tableattr 'id="tblgather" class="lineblk"'
SELECT (SELECT count(*) > 1 FROM pg_srvr WHERE connstr ilike 'You%') AS conlines \gset
\if :conlines
  \echo "There is serious problem with the data. Please make sure that all tables are dropped and recreated as part of importing data (gather_schema.sql) and there was no error"
  "SOMETHING WENT WRONG WHILE IMPORTING THE DATA. PLEASE MAKE SURE THAT ALL TABLES ARE DROPPED AND RECREATED AS PART OF IMPORTING";
  \q
\endif
\set tzone `echo "$PG_GATHER_TIMEZONE"`
SELECT * FROM 
(WITH TZ AS (SELECT CASE WHEN :'tzone' = ''
    THEN (SELECT set_config('timezone',setting,false) FROM pg_get_confs WHERE name='log_timezone')
    ELSE  set_config('timezone',:'tzone',false) 
  END AS val)
SELECT  UNNEST(ARRAY ['Collected At','Collected By','PG build', 'PG Start','In recovery?','Client','Server','Last Reload','Current LSN','Time Line','WAL file']) AS pg_gather,
        UNNEST(ARRAY [CONCAT(collect_ts::text,' (',TZ.val,')'),usr,ver, pg_start_ts::text ||' ('|| collect_ts-pg_start_ts || ')',recovery::text,client::text,server::text,reload_ts::text,
        current_wal::text,timeline::text || ' (Hex:' ||  upper(to_hex(timeline)) || ')',  lpad(upper(to_hex(timeline)),8,'0')||substring(pg_walfile_name(current_wal) from 9 for 16)]) AS "Report"
FROM pg_gather LEFT JOIN TZ ON TRUE 
UNION
SELECT  'Connection', replace(connstr,'You are connected to ','') FROM pg_srvr ) a WHERE "Report" IS NOT NULL ORDER BY 1;
\pset tableattr 'id="dbs" class="thidden"'
\C ''
WITH cts AS (SELECT COALESCE(collect_ts,(SELECT max(state_change) FROM pg_get_activity)) AS c_ts FROM pg_gather),
  wal_stat AS (SELECT stats_reset FROM pg_get_wal)
SELECT datname "DB Name",to_jsonb(ROW(tup_inserted/days,tup_updated/days,tup_deleted/days,to_char(pg_get_db.stats_reset,'YYYY-MM-DD HH24-MI-SS')))
,xact_commit/days "Avg.Commits",xact_rollback/days "Avg.Rollbacks",(tup_inserted+tup_updated+tup_deleted)/days "Avg.DMLs", CASE WHEN blks_fetch > 0 THEN blks_hit*100/blks_fetch ELSE NULL END  "Cache hit ratio"
,temp_files/days "Avg.Temp Files",temp_bytes/days "Avg.Temp Bytes",db_size "DB size",age "Age"
FROM pg_get_db LEFT JOIN wal_stat ON true
LEFT JOIN LATERAL (SELECT GREATEST((EXTRACT(epoch FROM(c_ts-COALESCE(pg_get_db.stats_reset,wal_stat.stats_reset)))/86400)::bigint,1) as days FROM cts) AS lat1 ON TRUE;
\pset tableattr off

\echo <div>
\echo <details style="clear: left; width: fit-content;">
\echo   <summary>Tune PostgreSQL Parameters (beta)</summary>
\echo   <label for="cpus">CPUs:
\echo   <input type="number" id="cpus" name="cpus" value="0">
\echo   </label>
\echo   <label for="mem" style="padding-left: 3em;">Memory(GB):
\echo   <input type="number" id="mem" name="mem" value="0">
\echo  </label>
\echo  <label for="strg" style="padding-left: 3em;"> Storage:
\echo   <select id="strg" name="strg">
\echo     <option value="ssd">SSD/NVMe</option>
\echo     <option value="san">SAN</option>
\echo     <option value="mag">Magnetic</option>
\echo    </select>
\echo  </label>
\echo  <label for="wrkld" style="padding-left: 3em;"> Work load:
\echo   <select id="wrkld" name="wrkld">
\echo     <option value="oltp">OLTP</option>
\echo     <option value="olap">OLAP</option>
\echo     <option value="mixed">Mixed</option>
\echo    </select>
\echo  </label>
\echo  <label for="flsys" style="padding-left: 3em;"> Filesystem:
\echo   <select id="flsys" name="flsys">
\echo     <option value="rglr">Regular (like: ext4/xfs)</option>
\echo     <option value="cow">COW (like: zfs/btrfs)</option>
\echo    </select>
\echo  </label>
\echo  <p style="border: 2px solid blue; border-radius: 5px; padding: 1em;">Please input the CPU and Memory available on the host machine for evaluating the current parameter settings<br />
\echo   Please see the tooltip against Parameters for recommendations based on calculations. Please seek expert advice</p>
\echo </details>
\echo </div>
\echo <h2 id="topics">Sections</h2>
\echo <ol>
\echo <li><a href="#tabInfo">Tables</a></li>
\echo <li><a href="#IndInfo">Indexes</a></li>
\echo <li><a href="#params">Parameters / Settings</a></li>
\echo <li><a href="#tblextn">Extensions</a></li>
\echo <li><a href="#tblcs">Connection & Users</a></li>
\echo <li><a href="#tableConten">Database Time</a></li>
\echo <li><a href="#tblsess">Session Details</a></li>
\echo <li><a href="#tblstmnt">Top Statements</a></li>
\echo <li><a href="#tblreplstat">Replications</a></li>
\echo <li><a href="#tblchkpnt" >BGWriter & Checkpointer</a></li>
\echo <li><a href="#finditem">Findings</a></li>
\echo </ol>
\echo <div id="bottommenu">
\echo  <a href="#topics" title="Sections">☰ Section Index (Alt+I)</a>
\echo  <div id="menu" style="display:none; position: relative">
\echo   <ol>
\echo     <li><a href="#tabInfo">Tables</a></li>
\echo     <li><a href="#IndInfo">Indexes</a></li>
\echo     <li><a href="#params">Parameters / Settings</a></li>
\echo     <li><a href="#tblextn">Extensions</a></li>
\echo     <li><a href="#tblcs">Connection & Users</a></li>
\echo     <li><a href="#tableConten">Database Time</a></li>
\echo     <li><a href="#tblsess">Session Details</a></li>
\echo     <li><a href="#tblstmnt">Top Statements</a></li>
\echo     <li><a href="#tblreplstat">Replications</a></li>
\echo     <li><a href="#tblchkpnt" >BGWriter & Checkpointer</a></li>
\echo     <li><a href="#finditem">Findings</a></li>
\echo   </ol>
\echo  </div>
\echo </div>
\echo <div id="sections" style="display:none">
\pset footer on
\pset tableattr 'id="tabInfo" class="thidden"'
SELECT c.relname || CASE WHEN c.relkind != 'r' THEN ' ('||c.relkind||')' ELSE '' END "Name" ,
to_jsonb(ROW(r.n_tup_ins,r.n_tup_upd,r.n_tup_del,r.n_tup_hot_upd,isum.totind,isum.ind0scan)),r.relnamespace "NS", CASE WHEN r.blks > 999 AND r.blks > tb.est_pages THEN (r.blks-tb.est_pages)*100/r.blks ELSE NULL END "Bloat%",
r.n_live_tup "Live",r.n_dead_tup "Dead", CASE WHEN r.n_live_tup <> 0 THEN  ROUND((r.n_dead_tup::real/r.n_live_tup::real)::numeric,1) END "D/L",
r.rel_size "Rel size",r.tot_tab_size "Tot.Tab size",r.tab_ind_size "Tab+Ind size",r.rel_age,to_char(r.last_vac,'YYYY-MM-DD HH24:MI:SS') "Last vacuum",to_char(r.last_anlyze,'YYYY-MM-DD HH24:MI:SS') "Last analyze",r.vac_nos,
ct.relname "Toast name",rt.tab_ind_size "Toast+Ind" ,rt.rel_age "Toast Age",GREATEST(r.rel_age,rt.rel_age) "Max age",
c.blocks_fetched "Fetch",c.blocks_hit*100/nullif(c.blocks_fetched,0) "C.Hit%"
FROM pg_get_rel r
JOIN pg_get_class c ON r.relid = c.reloid AND c.relkind NOT IN ('t','p')
LEFT JOIN pg_get_toast t ON r.relid = t.relid
LEFT JOIN pg_get_class ct ON t.toastid = ct.reloid
LEFT JOIN pg_get_rel rt ON rt.relid = t.toastid
LEFT JOIN pg_tab_bloat tb ON r.relid = tb.table_oid
LEFT JOIN (SELECT count(indexrelid) totind,count(indexrelid)FILTER( WHERE numscans=0 ) ind0scan,indrelid FROM pg_get_index GROUP BY indrelid ) AS isum ON isum.indrelid = r.relid
ORDER BY r.tab_ind_size DESC LIMIT 10000; 

\pset tableattr 'id="IndInfo"'
SELECT ct.relname AS "Table", ci.relname as "Index",indisunique as "UK?",indisprimary as "PK?",numscans as "Scans",size,ci.blocks_fetched "Fetch",ci.blocks_hit*100/nullif(ci.blocks_fetched,0) "C.Hit%"
  FROM pg_get_index i 
  JOIN pg_get_class ct on i.indrelid = ct.reloid and ct.relkind != 't'
  JOIN pg_get_class ci ON i.indexrelid = ci.reloid
ORDER BY size DESC LIMIT 10000;

\pset tableattr 'id="params"'
WITH dset AS (
SELECT string_agg(setting,chr(10)) setting,a.name FROM
(SELECT btrim(CASE WHEN rolname IS NULL THEN '' ELSE 'User: '|| rolname ||' , ' END || CASE WHEN datname IS NULL THEN '' ELSE 'DB: '|| datname END ,' ,') || ' ==> ' ||setting AS setting
,split_part(setting,'=',1) AS name
FROM pg_get_db_role_confs drc
LEFT JOIN LATERAL unnest(config) AS setting ON TRUE
LEFT JOIN pg_get_db db ON drc.db = db.datid
LEFT JOIN pg_get_roles rol ON rol.oid = drc.setrole
ORDER BY 1,2 NULLS LAST
) AS a GROUP BY 2 ),
fset AS (SELECT coalesce(s.name,f.name) AS name
,s.setting,s.unit,s.source
,string_agg(f.sourcefile ||' - '|| f.setting || CASE WHEN f.applied = true THEN ' (applicable)' ELSE '' END ,chr(10)) FILTER (WHERE s.source != f.sourcefile OR s.source IS NULL ) AS loc
FROM pg_get_confs s FULL OUTER JOIN pg_get_file_confs f ON lower(s.name) = lower(f.name)
GROUP BY 1,2,3,4 ORDER BY 1)
SELECT fset.name "Name",fset.setting "Setting",fset.unit "Unit",fset.source "Current Source",
CASE WHEN dset.setting IS NULL THEN '' ELSE dset.setting ||chr(10) END || CASE WHEN fset.loc IS NULL THEN '' ELSE fset.loc END AS "Other Locations & Values"
FROM fset LEFT JOIN dset ON fset.name = dset.name;

\pset tableattr 'id="tblextn"'
SELECT ext.oid,extname "Extension",rolname "Owner",nsname "Schema", extrelocatable "Relocatable?",extversion "Version" 
FROM pg_get_extension ext LEFT JOIN pg_get_roles ON extowner=pg_get_roles.oid
LEFT JOIN pg_get_ns ON extnamespace = nsoid;

\pset footer off
\pset tableattr 'id="tblcs" class="lineblk"'
\C 'DBConnections'
 SELECT d.datname "Database",state ,COUNT(pid) 
  FROM pg_get_activity a LEFT JOIN pg_get_db d on a.datid = d.datid
    WHERE state is not null GROUP BY 1,2 ORDER BY 1;

\pset tableattr 'id="tblusr" class="thidden"'
WITH rol_db AS (SELECT 
rolname,datname,count(*) FILTER (WHERE state='active') as active,
count(*) FILTER (WHERE state='idle in transaction') as idle_in_transaction,
count(*) FILTER (WHERE state='idle') as idle,
count(*) as totalcons,
count (*) FILTER (WHERE ssl = true) as sslcons,
count (*) FILTER (WHERE ssl = false) as nonsslcons
FROM pg_get_activity 
  join pg_get_roles on usesysid=pg_get_roles.oid
  join pg_get_db on pg_get_activity.datid = pg_get_db.datid
GROUP BY 1,2
ORDER BY 1,2),
rol AS (SELECT rolname,sum(active) "Active",sum(idle_in_transaction) "IdleInTrans",sum(idle) "Idle",sum(totalcons) "TotalCons",sum(sslcons) "SSLCons",sum(nonsslcons) "NonSSLCons"
FROM rol_db GROUP BY 1)
SELECT pg_get_roles.rolname "User",
(SELECT json_agg(ROW(datname,active,idle_in_transaction,idle,totalcons,sslcons,nonsslcons)) FROM rol_db WHERE rol_db.rolname = pg_get_roles.rolname),
rolsuper "Super?",rolreplication "Repl?", CASE WHEN rolconnlimit > -1 THEN rolconnlimit ELSE NULL END  "Limit", 
CASE enc_method WHEN 'm' THEN 'MD5' WHEN 'S' THEN 'SCRAM' END "Enc",
"Active","IdleInTrans","Idle","TotalCons","SSLCons","NonSSLCons"
FROM pg_get_roles LEFT JOIN rol ON pg_get_roles.rolname = rol.rolname;

\pset tableattr 'id="tableConten" name="waits" style="clear: left"'
\C 'WaitEvents'
SELECT COALESCE(wait_event,'CPU') "Event", count(*)::text FROM pg_pid_wait
WHERE wait_event IS NULL OR wait_event NOT IN ('ArchiverMain','AutoVacuumMain','BgWriterHibernate','BgWriterMain','CheckpointerMain','LogicalApplyMain','LogicalLauncherMain','RecoveryWalStream','SysLoggerMain','WalReceiverMain','WalSenderMain','WalWriterMain','CheckpointWriteDelay','PgSleep','VacuumDelay')
GROUP BY 1 ORDER BY count(*) DESC;

\pset tableattr 'id="tblsess" class="thidden"' 
\C 'Sessions'
SELECT * FROM (
    WITH w AS (SELECT pid, string_agg( wait_event ||':'|| cnt,',') waits, sum(cnt) pidwcnt, max(max) itr_max, min(min) itr_min FROM
    (SELECT pid,COALESCE(wait_event,'CPU') wait_event,count(*) cnt, max(itr),min(itr) FROM pg_pid_wait GROUP BY 1,2 ORDER BY cnt DESC) pw GROUP BY 1),
  g AS (SELECT MAX(state_change) as ts,MAX(GREATEST(backend_xid::text::bigint,backend_xmin::text::bigint)) mx_xid FROM pg_get_activity),
  itr AS (SELECT max(itr_max) gitr_max FROM w)
  SELECT a.pid,to_jsonb(ROW(d.datname,application_name,client_hostname,sslversion)), a.state,r.rolname "User",client_addr "client"
  , CASE query WHEN '' THEN '**'||backend_type||' process**' ELSE query END "Last statement"
  , g.ts - backend_start "Connection Since", g.ts - xact_start "Transaction Since", g.mx_xid - backend_xmin::text::bigint "xmin age",
   g.ts - query_start "Statement since",g.ts - state_change "State since", w.waits ||
   CASE WHEN (itr_max - itr_min)::float/itr.gitr_max*2000 - pidwcnt > 0 THEN
    ', Net/Delay*:' || ((itr_max - itr_min)::float/itr.gitr_max*2000 - pidwcnt)::int
   ELSE '' END waits
  FROM pg_get_activity a 
   LEFT JOIN w ON a.pid = w.pid
   LEFT JOIN itr ON true
   LEFT JOIN g ON true
   LEFT JOIN pg_get_roles r ON a.usesysid = r.oid
   LEFT JOIN pg_get_db d on a.datid = d.datid
  ORDER BY "xmin age" DESC NULLS LAST) AS sess
WHERE waits IS NOT NULL OR state != 'idle';

\pset tableattr 'id="tblstmnt"'
\C 'Top Statements'
SELECT DENSE_RANK() OVER (ORDER BY ranksum) "Rank", "Statement",time_pct "DB.time%", calls "Execs",total_time::bigint/calls "Avg.ExecTime","Avg.Reads","C.Hit%" 
,"Avg.Dirty","Avg.Write","Avg.Temp(r)","Avg.Temp(w)" FROM 
(select query "Statement",total_time::bigint
, round((100*total_time/sum(total_time) OVER ())::numeric,2) AS time_pct, DENSE_RANK() OVER (ORDER BY total_time DESC) AS tottrank,calls
,total_time::bigint/calls, DENSE_RANK() OVER (ORDER BY total_time::bigint/calls DESC) as avgtrank
,DENSE_RANK() OVER (ORDER BY total_time DESC)+DENSE_RANK() OVER (ORDER BY total_time::bigint/calls DESC) ranksum
,shared_blks_read/calls "Avg.Reads",
shared_blks_dirtied/calls "Avg.Dirty",
shared_blks_written/calls "Avg.Write",
temp_blks_read/calls "Avg.Temp(r)",
temp_blks_written/calls "Avg.Temp(w)"
,100 * shared_blks_hit / nullif((shared_blks_read + shared_blks_hit),0) as "C.Hit%"
from pg_get_statements) AS stmnts
WHERE tottrank < 10 OR avgtrank < 10 ;

\pset tableattr 'id="tblreplstat"'
WITH M AS (SELECT GREATEST((SELECT(current_wal) FROM pg_gather),(SELECT MAX(sent_lsn) FROM pg_replication_stat))),
  g AS (SELECT MAX(GREATEST(backend_xid::text::bigint,backend_xmin::text::bigint)) mx_xid FROM pg_get_activity)
SELECT usename AS "Replication User",client_addr AS "Replica Address",pid,state,
 pg_wal_lsn_diff(M.greatest, sent_lsn) "Transmission Lag (Bytes)",pg_wal_lsn_diff(sent_lsn,write_lsn) "Replica Write lag(Bytes)",
 pg_wal_lsn_diff(write_lsn,flush_lsn) "Replica Flush lag(Bytes)",pg_wal_lsn_diff(flush_lsn,replay_lsn) "Replay at Replica lag(Bytes)",
 slot_name "Slot",plugin,slot_type "Type",datname "DB name",temporary,active,GREATEST(g.mx_xid-old_xmin::text::bigint,0) as "xmin age",
 GREATEST(g.mx_xid-catalog_xmin::text::bigint,0) as "catalog xmin age", GREATEST(pg_wal_lsn_diff(M.greatest,restart_lsn),0) as "Restart LSN lag(Bytes)",
 GREATEST(pg_wal_lsn_diff(M.greatest,confirmed_flush_lsn),0) as "Confirmed LSN lag(Bytes)"
FROM pg_replication_stat JOIN M ON TRUE
  FULL OUTER JOIN pg_get_slots s ON pid = active_pid
  LEFT JOIN g ON TRUE
  LEFT JOIN pg_get_db ON s.datoid = datid;

\pset tableattr 'id="tblchkpnt"'
\C 'Analysis of Background writer and Checkpointer Process'
SELECT round(checkpoints_req*100/tot_cp,1) "Forced Checkpoint %" ,
round(min_since_reset/tot_cp,2) "avg mins between CP",
round(checkpoint_write_time::numeric/(tot_cp*1000),4) "Avg CP write time (s)",
round(checkpoint_sync_time::numeric/(tot_cp*1000),4)  "Avg CP sync time (s)",
round(total_buffers::numeric*8192/(1024*1024),2) "Tot MB Written",
round((buffers_checkpoint::numeric/tot_cp)*8192/(1024*1024),4) "MB per CP",
round(buffers_checkpoint::numeric*8192/(min_since_reset*60*1024*1024),4) "Checkpoint MBps",
round(buffers_clean::numeric*8192/(min_since_reset*60*1024*1024),4) "Bgwriter MBps",
round(buffers_backend::numeric*8192/(min_since_reset*60*1024*1024),4) "Backend MBps",
round(total_buffers::numeric*8192/(min_since_reset*60*1024*1024),4) "Total MBps",
round(buffers_alloc::numeric/total_buffers,3)  "New buffers ratio",
round(100.0*buffers_checkpoint/total_buffers,1)  "Clean by checkpoints (%)",
round(100.0*buffers_clean/total_buffers,1)   "Clean by bgwriter (%)",
round(100.0*buffers_backend/total_buffers,1)  "Clean by backends (%)",
round(100.0*maxwritten_clean/(min_since_reset*60000 / delay.setting::numeric),2)   "Bgwriter halts (%) per runs",
coalesce(round(100.0*maxwritten_clean/(nullif(buffers_clean,0)/ lru.setting::numeric),2),0)  "Bgwriter halt (%) due to LRU hit",
round(min_since_reset/(60*24),1) "Reset days"
FROM pg_get_bgwriter
CROSS JOIN 
(SELECT 
    NULLIF(round(extract('epoch' from (select collect_ts from pg_gather) - stats_reset)/60)::numeric,0) min_since_reset,
    GREATEST(buffers_checkpoint + buffers_clean + buffers_backend,1) total_buffers,
    NULLIF(checkpoints_timed+checkpoints_req,0) tot_cp 
    FROM pg_get_bgwriter) AS bg
LEFT JOIN pg_get_confs delay ON delay.name = 'bgwriter_delay'
LEFT JOIN pg_get_confs lru ON lru.name = 'bgwriter_lru_maxpages'; 
\echo <ol id="finditem" style="padding:2em;position:relative">
\echo <h3 style="font: italic bold 2em Georgia, serif;text-decoration: underline; margin: 0 0 0.5em;">Findings:</h3>
\pset format aligned
\pset tuples_only on
WITH W AS (SELECT COUNT(*) AS val FROM pg_get_activity WHERE state='idle in transaction')
SELECT CASE WHEN val > 0 
  THEN '<li><b>'||val||' idle-in-transaction</b> session(s). Sessions in idle-in-transaction can cause poor concurrency </li>' 
  ELSE NULL END 
FROM W;
WITH W AS (select last_failed_time,last_archived_time,last_archived_wal from pg_archiver_stat where last_archived_time < last_failed_time)
SELECT CASE WHEN last_archived_time IS NOT NULL
  THEN '<li>WAL archiving is failing since <b>'||last_archived_time||' (duration:'|| (SELECT COALESCE(collect_ts,(SELECT max(state_change) FROM pg_get_activity)) AS c_ts FROM pg_gather) - last_archived_time  ||') onwards</b> '  ||
  CASE WHEN length(last_archived_wal)=24 THEN COALESCE(
  (SELECT ' With estimated size <b>' ||
  pg_size_pretty(((('x'||lpad(split_part(current_wal::TEXT,'/', 1),8,'0'))::bit(32)::bigint - ('x'||substring(last_archived_wal,9,8))::bit(32)::bigint) * 255 * 16^6 + 
  ('x'||lpad(split_part(current_wal::TEXT,'/', 2),8,'0'))::bit(32)::bigint - ('x'||substring(last_archived_wal,17,8))::bit(32)::bigint*16^6 )::bigint)
  FROM pg_gather), ' ') || '</b> behind </li>' ELSE '</li>' END
ELSE NULL END
FROM W;
WITH W AS (select count(*) AS val from pg_get_index i join pg_get_class ct on i.indrelid = ct.reloid and ct.relkind != 't')
SELECT CASE WHEN val > 10000
  THEN '<li>There are <b>'||val||' indexes!</b> in this database, Only biggest 10000 will be listed in this report under <a href= "#indexes" >Index Info</a>. Please use query No. 11. from the analysis_quries.sql for full details </li>'
  ELSE NULL END
FROM W;
WITH W AS (
 select string_agg(name ||'='||setting,',') as val FROM pg_get_confs WHERE 
 name in ('block_size','max_identifier_length','max_function_args','max_index_keys','segment_size','wal_block_size') AND 
 (name,setting) NOT IN (('block_size','8192'),('max_identifier_length','63'),('max_function_args','100'),('max_index_keys','32'),('segment_size','131072'),('wal_block_size','8192'))
 OR (name = 'wal_segment_size' AND unit ='8kB' and setting != '2048') OR (name = 'wal_segment_size' AND unit ='B' and setting != '16777216')  
)
SELECT CASE WHEN LENGTH(val) > 1
  THEN '<li>Detected Non-Standard Compile/Initialization time parameter changes <b>'||val||' </b>. Custom Compilation is prone to bugs, and it is beyond supportability</li>'
  ELSE NULL END
FROM W;
WITH W AS (
SELECT count(*) cnt FROM pg_get_confs WHERE source IS NOT NULL )
SELECT CASE WHEN cnt < 1
  THEN '<li>Couldn''t get parameter values. Partial gather or corrupt Parameter file(s)</li>'
  ELSE NULL END
FROM W;
SELECT '<li>Parameter '||error ||': '||name||' = '||setting||' in '||sourcefile||'</li>' FROM pg_get_file_confs WHERE error IS NOT NULL;

\echo </ol>
\echo <div id="analdata" hidden>
\pset format unaligned
SELECT to_jsonb(r) FROM
(SELECT 
  (select recovery from pg_gather) AS clsr,
  (SELECT to_jsonb(ROW(count(*),COUNT(*) FILTER (WHERE last_vac IS NULL),COUNT(*) FILTER (WHERE last_anlyze IS NULL))) 
     from pg_get_rel r JOIN pg_get_class c ON r.relid = c.reloid AND c.relkind NOT IN ('t','p')) AS tabs,
  (SELECT to_jsonb(ROW(COUNT(*),COUNT(*) FILTER (WHERE CONN < interval '15 minutes' ) )) FROM 
    (WITH g AS (SELECT MAX(state_change) as ts FROM pg_get_activity)
    SELECT pid,g.ts - backend_start CONN
    FROM pg_get_activity
    LEFT JOIN g ON true
    WHERE EXISTS (SELECT pid FROM pg_pid_wait WHERE pid=pg_get_activity.pid)
    AND backend_type='client backend') cn) AS cn,
  (SELECT to_jsonb(ROW(count(*) FILTER (WHERE relkind='p'), max(reloid))) from pg_get_class) as clas,
  (SELECT to_jsonb(ROW(count(*) FILTER (WHERE state='active' AND state IS NOT NULL), 
  count(*) FILTER (WHERE state='idle in transaction'), count(*) FILTER (WHERE state='idle'),
  count(*) FILTER (WHERE state IS NULL), count(*) FILTER (WHERE leader_pid IS NOT NULL) ,
  count(*),   count(distinct backend_type)))
  FROM pg_get_activity) as sess,
  (WITH curdb AS (SELECT trim(both '\"' from substring(connstr from '\"\w*\"')) "curdb" FROM pg_srvr WHERE connstr like '%to database%'),
    cts AS (SELECT COALESCE((SELECT COALESCE(collect_ts,(SELECT max(state_change) FROM pg_get_activity)) FROM pg_gather),current_timestamp) AS c_ts)
    SELECT to_jsonb(ROW(curdb,COALESCE(pg_get_db.stats_reset,pg_get_wal.stats_reset),c_ts,days))
    FROM  curdb LEFT JOIN pg_get_db ON pg_get_db.datname=curdb.curdb
    LEFT JOIN pg_get_wal ON true
    LEFT JOIN LATERAL (SELECT GREATEST((EXTRACT(epoch FROM(c_ts- COALESCE(pg_get_db.stats_reset,pg_get_wal.stats_reset)))/86400)::bigint,1) as days FROM cts) AS lat1 ON TRUE
    LEFT JOIN cts ON true ) as dbts,
  (SELECT json_agg(pg_get_ns) FROM  pg_get_ns WHERE nsoid > 16384 OR nsname='public') AS ns,
  (SELECT to_jsonb( ROW((collect_ts - last_archived_time) > '15 minute' :: interval, pg_wal_lsn_diff( current_wal,
  (coalesce(nullif(CASE WHEN length(last_archived_wal) < 24 THEN '' ELSE ltrim(substring(last_archived_wal, 9, 8), '0') END, ''), '0') || '/' || substring(last_archived_wal, 23, 2) || '000001'        ) :: pg_lsn )))
  FROM  pg_gather,  pg_archiver_stat) AS arcfail,
  (SELECT to_jsonb(ROW(max(setting) FILTER (WHERE name = 'archive_library'), max(setting) FILTER (WHERE name = 'cluster_name'),count(*) FILTER (WHERE source = 'command line'))) FROM pg_get_confs) AS params,
  (SELECT CASE WHEN max(stats_reset)-min(stats_reset) < '2 minute' :: interval THEN min(stats_reset) ELSE NULL END 
  FROM (SELECT stats_reset FROM pg_get_db UNION SELECT stats_reset FROM pg_get_bgwriter) reset) crash,
  (WITH blockers AS (select array_agg(victim_pid) OVER () victim,blocking_pids blocker from pg_get_pidblock),
   ublokers as (SELECT unnest(blocker) AS blkr FROM blockers)
   SELECT json_agg(blkr) FROM ublokers
   WHERE NOT EXISTS (SELECT 1 FROM blockers WHERE ublokers.blkr = ANY(victim))) blkrs,
  (select json_agg((victim_pid,blocking_pids)) from pg_get_pidblock) victims,
  (select to_jsonb((EXTRACT(epoch FROM (end_ts-collect_ts)),pg_wal_lsn_diff(end_lsn,current_wal)*60*60/EXTRACT(epoch FROM (end_ts-collect_ts)))) 
  from pg_gather,pg_gather_end) sumry,
  (SELECT json_agg((relname,maint_work_mem_gb)) FROM (SELECT relname,n_live_tup*0.2*6 maint_work_mem_gb 
   FROM pg_get_rel JOIN pg_get_class ON n_live_tup > 894784853 AND pg_get_rel.relid = pg_get_class.reloid 
   ORDER BY 2 DESC LIMIT 3) AS wmemuse) wmemuse,
   (SELECT to_jsonb(ROW(count(*) FILTER (WHERE indisvalid=false),count(*) FILTER (WHERE numscans=0),count(*),sum(size) FILTER (WHERE numscans=0))) FROM pg_get_index) induse,
   (SELECT to_jsonb(ROW(sum(tab_ind_size) FILTER (WHERE relid < 16384),count(*))) FROM pg_get_rel) meta
) r;

\echo </div>
\echo </div> <!--End of "sections"-->
\echo <footer>End of <a href="https://github.com/jobinau/pg_gather">pgGather</a> Report</footer>
\echo <script type="text/javascript">
\echo obj={};
\echo ver="24";
\echo meta={pgvers:["11.21","12.17","13.13","14.10","15.5","16.1"],commonExtn:["plpgsql","pg_stat_statements"],riskyExtn:["citus","tds_fdw"]};
\echo mgrver="";
\echo walcomprz="";
\echo autovacuum_freeze_max_age = 0;
\echo let strfind = "";
\echo totdb=0;
\echo totCPU=0;
\echo totMem=0;
\echo let blokers = []
\echo let blkvictims = []
\echo let params = []
\echo document.addEventListener("DOMContentLoaded", () => {
\echo obj=JSON.parse( document.getElementById("analdata").innerText);
\echo if (obj.victims !== null){
\echo obj.victims.forEach(function(victim){
\echo   blkvictims.push(victim.f1);
\echo });
\echo obj.victims.forEach(function(victim){
\echo   victim.f2.forEach(function(blker){
\echo     if (blkvictims.indexOf(blker) == -1 && blokers.indexOf(blker) == -1) blokers.push(blker);
\echo   });
\echo });
\echo }
\echo checkgather();
\echo checkpars();
\echo checktabs();
\echo checkindex();
\echo checkdbs();
\echo checkextn();
\echo checkusers();
\echo checksess();
\echo checkstmnts();
\echo checkchkpntbgwrtr();
\echo checkfindings();
\echo });
\echo window.onload = function() {
\echo   document.getElementById("sections").style="display:table";
\echo   document.getElementById("busy").style="display:none";
\echo };
\echo function checkgather(){
\echo    const trs=document.getElementById("tblgather").rows
\echo   for (let i = 0; i < trs.length; i++) {
\echo     val = trs[i].cells[1];
\echo     switch(trs[i].cells[0].innerText){
\echo       case "pg_gather" :
\echo         val.innerText = val.innerText + "-v" + ver;
\echo         break;
\echo       case "Collected By" :
\echo         if (val.innerText.slice(-2) < ver ) { val.classList.add("warn"); val.title = "Data collected using old version of gather.sql file. Please use v" + ver; 
\echo         strfind += "<li>Data collected using old version (v"+ val.innerText.slice(-2) + ") of gather.sql file. Please use v" + ver + "</li>";
\echo         }
\echo         break;
\echo       case "In recovery?" :
\echo         console.log(val.innerText);
\echo         if(val.innerText == "true") {val.classList.add("lime"); val.title="Data collected at standby"; obj.primary = false;}
\echo         else obj.primary = true; 
\echo         break;
\echo     }
\echo   }
\echo }
\echo function checkfindings(){
\echo  if (obj.sess.f7 < 4){ 
\echo   strfind += "<li><b>The pg_gather data is collected by a user who don't have necessary privilege OR Content of the output file (out.txt) is copy-pasted destroying the TSV format</b><br/><b>1.</b>Please run the gather.sql as a privileged user (superuser, rds_superuser etc.) or some account with pg_monitor privilege and <b>2.</b> Please provide the output file as it is without copy-pasting</li>"
\echo   document.getElementById("tableConten").title="Waitevents data will be growsly incorrect because the pg_gather data is collected by a user who don't have proper privilege OR content of output file is copy-pasted. Please refer the Findings section";
\echo   document.getElementById("tableConten").caption.innerHTML += "<br/>" + document.getElementById("tableConten").title
\echo   document.getElementById("tableConten").classList.add("high");
\echo  }
\echo  if (obj.cn.f1 > 0){
\echo     strfind +="<li><b>" + obj.cn.f2 + " / " + obj.cn.f1 + " connections </b> in use are new. "
\echo     if (obj.cn.f2 > 9 || obj.cn.f2/obj.cn.f1 > 0.7 ){
\echo       strfind+="Please consider this for improving connection pooling"
\echo     } 
\echo     strfind += "</li>";
\echo  }
\echo  if (obj.induse.f1 > 0 ) strfind += "<li><b>"+ obj.induse.f1 +" Invalid Index(es)</b> found. Recreate or drop them. Refer <a href='https://github.com/jobinau/pg_gather/blob/main/docs/InvalidIndexes.md'>Link</a></li>";
\echo  if (obj.induse.f2 > 0 ) strfind += "<li><b>"+ obj.induse.f2 +" out of " + obj.induse.f3 + " Index(es) are Unused, Which accounts for "+ bytesToSize(obj.induse.f4) +"</b>. Consider dropping of all unused Indexes</li>";
\echo  if (obj.clas.f1 > 0) strfind += "<li><b>"+ obj.clas.f1 +" Natively partitioned tables</b> found. Tables section could contain partitions</li>";
\echo  if (obj.params.f3 > 10) strfind += "<li> Patroni/HA PG cluster :<b>" + obj.params.f2 + "</b></li>"
\echo  if(obj.clsr){
\echo   strfind += "<li>PostgreSQL is in Standby mode or in Recovery</li>";
\echo  }else{
\echo   if ( obj.tabs.f2 > 0 ) strfind += "<li> <b>No vacuum info for " + obj.tabs.f2 + "</b> tables </li>";
\echo   if ( obj.tabs.f3 > 0 ) strfind += "<li> <b>No statistics available for " + obj.tabs.f3 + " tables</b>, query planning can go wrong </li>";
\echo   if ( obj.tabs.f1 > 10000) strfind += "<li> There are <b>" + obj.tabs.f1 + " tables</b> in the database. Only the biggest 10000 will be displayed in the report. Avoid too many tables in single database. You may use backend query (Query No.10) from analysis_queries.sql</li>";
\echo   if (obj.arcfail != null) {
\echo    if (obj.arcfail.f1 == null) strfind += "<li>No working WAL archiving and backup detected. PITR may not be possible</li>";
\echo    if (obj.arcfail.f1) strfind += "<li>No WAL archiving happened in last 15 minutes <b>archiving could be failing</b>; please check PG logs</li>";
\echo    if (obj.arcfail.f2 && obj.arcfail.f2 > 0) strfind += "<li>WAL archiving is <b>lagging by "+ bytesToSize(obj.arcfail.f2,1024)  +"</b></li>";
\echo   }
\echo   if (obj.wmemuse !== null && obj.wmemuse.length > 0){ strfind += "<li> Biggest <code>maintenance_work_mem</code> consumers are :<b>"; obj.wmemuse.forEach(function(t,idx){ strfind += (idx+1)+". "+t.f1 + " (" + bytesToSize(t.f2) + ")    " }); strfind += "</b></li>"; }
\echo   if (obj.victims !== null && obj.victims.length > 0) strfind += "<li><b>" + obj.victims.length + " session(s) blocked.</b></li>"
\echo   if (obj.sumry !== null){ strfind += "<li>Data collection took <b>" + obj.sumry.f1 + " seconds. </b>";
\echo      if ( obj.sumry.f1 < 23 ) strfind += "System response is good</li>";
\echo      else if ( obj.sumry.f1 < 28 ) strfind += "System response is below average</li>";
\echo      else strfind += "System response appears to be poor</li>";
\echo      strfind += "<li>Current WAL generation rate is <b>" + bytesToSize(obj.sumry.f2) + " / hour</b></li>"; }
\echo   if ( mgrver.length > 0 &&  mgrver < Math.trunc(meta.pgvers[0])) strfind += "<li>PostgreSQL <b>Version : " + mgrver + " is outdated (EOL) and not supported</b>, Please upgrade urgently</li>";
\echo   if ( mgrver >= 15 && ( walcomprz == "off" || walcomprz == "on")) strfind += "<li>The <b>wal_compression is '" + walcomprz + "' on PG"+ mgrver +"</b>, consider a good compression method (lz4,zstd)</li>"
\echo   if (obj.ns !== null){
\echo    let tempNScnt = obj.ns.filter(n => n.nsname.indexOf("pg_temp") > -1).length + obj.ns.filter(n => n.nsname.indexOf("pg_toast_temp") > -1).length ;
\echo    tmpfind = "<li><b>" + (obj.ns.length - tempNScnt).toString()  + " user schema(s) and " + tempNScnt + " temporary schema(s)</b> in this database.";
\echo    if (tempNScnt > 0 && obj.clas.f2 > 50000) tmpfind += "<br>Currently oid of pg_class stands at " + Number(obj.clas.f2).toLocaleString("en-US") + " <b>indicating the usage of temp tables</b>"
\echo    strfind += tmpfind + "</li>";
\echo   }
\echo   if (obj.meta.f1 > 15728640){
\echo     strfind += "<li>" + "The catalog metadata is :<b>" + bytesToSize(obj.meta.f1) + " For " + obj.meta.f2 + " objects. </b><a href='https://github.com/jobinau/pg_gather/blob/main/docs/catalogbloat.md'> Link<a></li>"
\echo   }
\echo  }
\echo   document.getElementById("finditem").innerHTML += strfind;
\echo   var el=document.createElement("tfoot");
\echo   el.innerHTML = "<th colspan='9'>**Averages are Per Day. Total size of "+ (document.getElementById("dbs").tBodies[0].rows.length - 1) +" DBs : "+ bytesToSize(totdb) +"</th>";
\echo   dbs=document.getElementById("dbs");
\echo   dbs.appendChild(el);
\echo   el=document.createElement("tfoot");
\echo   el.innerHTML = "<th colspan='3'>Active: "+ obj.sess.f1 +", Idle-in-transaction: " + obj.sess.f2 + ", Idle: " + obj.sess.f3 + ", Background: " + obj.sess.f4 + ", Workers: " + obj.sess.f5 + ", Total: " + obj.sess.f6 + "</th>";
\echo   tblcs=document.getElementById("tblcs");
\echo   tblcs.appendChild(el);
\echo   tblcs.caption.innerHTML=''''<span>DB Connections</span>'''';
\echo }
\echo document.getElementById("cpus").addEventListener("change", (event) => {
\echo   totCPU = event.target.value;
\echo   checkpars();  
\echo });
\echo document.getElementById("mem").addEventListener("change", (event) => {
\echo   totMem = event.target.value;
\echo   checkpars();  
\echo });
\echo function bytesToSize(bytes,divisor = 1000) {
\echo   const sizes = ["B","KB","MB","GB","TB"];
\echo   if (bytes == 0) return "0B";
\echo   const i = parseInt(Math.floor(Math.log(bytes) / Math.log(divisor)), 10);
\echo   if (i === 0) return bytes + sizes[i];
\echo   return (bytes / (divisor ** i)).toFixed(1) + sizes[i]; 
\echo }
\echo function DurationtoSeconds(duration){
\echo     const [hours, minutes, seconds] = duration.split(":");
\echo     return Number(hours) * 60 * 60 + Number(minutes) * 60 + Number(seconds);
\echo };
\echo var paramDespatch = {
\echo   archive_mode : function(rowref){
\echo     val=rowref.cells[1];
\echo     if(obj.primary  == true && val.innerHTML == "off"){ val.classList.add("warn"); val.title="Primary server without WAL archiving configured. No PITR possible"}
\echo   },
\echo   archive_command : function(rowref) {
\echo     val=rowref.cells[1];
\echo     if (obj.params !== null && obj.params.f1 !== null && obj.params.f1.length > 0) { val.classList.add("warn"); val.title="archive_command won't be in-effect, because archive_library : " + obj.arclib + " is specified"  }
\echo     else if (val.innerText.length < 5) {val.classList.add("warn"); val.title="A valid archive_command is expected for WAL archiving, unless archive library is used" ; }
\echo   },
\echo   autovacuum : function(rowref) {
\echo     val=rowref.cells[1];
\echo     if(val.innerText != "on") { val.classList.add("warn"); val.title="Autovacuum must be on" }
\echo   },
\echo   autovacuum_max_workers : function(rowref) {
\echo     val=rowref.cells[1];
\echo     if(val.innerText > 3) { val.classList.add("warn"); val.title="High number of workers causes each workers to run slower because of the cost limit" }
\echo   },
\echo   autovacuum_vacuum_cost_limit: function(rowref){
\echo     val=rowref.cells[1];
\echo     if(val.innerText > 800 || val.innerText == -1 ) { val.classList.add("warn"); val.title="Better to specify this with a value less than 800" }
\echo   },
\echo   autovacuum_freeze_max_age: function(rowref){
\echo     val=rowref.cells[1];
\echo     autovacuum_freeze_max_age = Number(val.innerText); 
\echo     if (autovacuum_freeze_max_age > 800000000) val.classList.add("warn");
\echo   },
\echo   checkpoint_timeout: function(rowref){
\echo     val=rowref.cells[1];
\echo     if(val.innerText < 1200) { val.classList.add("warn"); val.title="Too small gap between checkpoints"}
\echo   },
\echo   shared_buffers: function(rowref){
\echo     val=rowref.cells[1];
\echo     val.classList.add("lime"); val.title=bytesToSize(val.innerText*8192,1024);
\echo     if( totMem > 0 && ( totMem < val.innerText*8*0.2/1048576 || totMem > val.innerText*8*0.3/1048576 ))
\echo       { val.classList.add("warn"); val.title="Approx. 25% of available memory is recommended, current value of " + bytesToSize(val.innerText*8192,1024) + " appears to be off" }
\echo   },
\echo   max_connections: function(rowref){
\echo     val=rowref.cells[1];
\echo     val.title="Avoid value exceeding 10x of the CPUs"
\echo     if( totCPU > 0 ){
\echo       if(val.innerText > 10 * totCPU) { val.classList.add("warn"); val.title="If there is only " + totCPU + " CPUs value above " + 10*totCPU + " Is not recommendable for performance and stability" }
\echo         else { val.classList.remove("warn"); val.classList.add("lime"); val.title="Current value is good" }
\echo         } else if (val.innerText > 500) val.classList.add("warn")
\echo       else val.classList.add("lime")
\echo   },
\echo   deadlock_timeout: function(rowref){ val=rowref.cells[1]; val.classList.add("lime"); },
\echo   effective_cache_size: function(rowref){ val=rowref.cells[1]; val.classList.add("lime"); val.title=bytesToSize(val.innerText*8192,1024); }, 
\echo   huge_pages: function(rowref){ val=rowref.cells[1]; val.classList.add("lime"); },
\echo   huge_page_size: function(rowref){ val=rowref.cells[1]; val.classList.add("lime"); },
\echo   hot_standby_feedback: function(rowref){ val=rowref.cells[1]; val.classList.add("lime"); },
\echo   idle_session_timeout:function(rowref){ 
\echo     val=rowref.cells[1]; 
\echo     if (val.innerText > 0) { val.classList.add("warn"); val.title="It is dangerous to use idle_session_timeout. Avoid using this" }
\echo   },
\echo   idle_in_transaction_session_timeout: function(rowref){ 
\echo     val=rowref.cells[1]; 
\echo     if (val.innerText == 0){ val.classList.add("warn"); val.title="Highly suggestable to use atleast 5min to prevent application misbehaviour" }
\echo   },
\echo   jit: function(rowref){ val=rowref.cells[1]; if (val.innerText=="on") { val.classList.add("warn"); 
\echo     val.title="Avoid JIT globally (Disable), Use only at smaller scope" }},
\echo   log_temp_files: function(rowref){
\echo     val = val=rowref.cells[1];
\echo     let param = params.find(p => p.param === "log_temp_files");
\echo     if (typeof param["suggest"] != "undefined"){
\echo       val.classList.add("warn"); 
\echo       val.title="Heavy temporary file generation is detected. Consider setting log_temp_files=" + param["suggest"] + "MB";
\echo     } else if ((param["val"] > -1)){
\echo       val.classList.add("lime");
\echo       val.title="log_temp_files is already set. Analyze PostgreSQL log for problematic SQLs. Adjust parameter value if required";
\echo     }
\echo   },
\echo   log_lock_waits: function(rowref){},
\echo   maintenance_work_mem: function(rowref){ val=rowref.cells[1]; val.classList.add("lime"); val.title=bytesToSize(val.innerText*1024,1024); },
\echo   max_wal_size: function(rowref){
\echo     val=rowref.cells[1];
\echo     val.title=bytesToSize(val.innerText*1024*1024,1024);
\echo     if(val.innerText < 8192) { val.classList.add("warn"); val.title += ",Too low for production use" }
\echo     else val.classList.add("lime");
\echo   },
\echo   min_wal_size: function(rowref){
\echo     val=rowref.cells[1];
\echo     val.title=bytesToSize(val.innerText*1024*1024,1024);
\echo     if(val.innerText < 2048) {val.classList.add("warn"); val.title+=",Too low for production use" }
\echo     else val.classList.add("lime");
\echo   },
\echo   random_page_cost: function(rowref){
\echo     val=rowref.cells[1];
\echo     if(val.innerText > 1.2) val.classList.add("warn");
\echo   },
\echo   server_version: function(rowref){
\echo     val=rowref.cells[1];
\echo     let setval = val.innerText.split(" ")[0]; mgrver=setval.split(".")[0];
\echo     if ( mgrver < Math.trunc(meta.pgvers[0])){
\echo       val.classList.add("warn"); val.title="PostgreSQL Version is outdated (EOL) and not supported";
\echo     } else {
\echo       meta.pgvers.forEach(function(t){
\echo         if (Math.trunc(setval) == Math.trunc(t)){
\echo           if (t.split(".")[1] - setval.split(".")[1] > 0 ) { val.classList.add("warn"); val.title= t.split(".")[1] - setval.split(".")[1] + " minor version updates pending. Please upgrade ASAP"; }
\echo         }
\echo       })  
\echo     }
\echo     if(val.classList.length < 1) val.classList.add("lime"); 
\echo   },
\echo   statement_timeout : function(rowref){
\echo     val=rowref.cells[1];
\echo     if(rowref.cells[3].innerText == "session" && rowref.cells[4].innerText.trim() == ""){
\echo       val.classList.add("warn"); val.title="Session level setting of pg_gather. It is important to set a value globally to avoid long running sessions and associated problems"
\echo     }
\echo   },
\echo   synchronous_standby_names: function(rowref){
\echo     val=rowref.cells[1];
\echo     if (val.innerText.trim().length > 0){ val.classList.add("warn"); val.title="Synchronous Standby can cause session hangs, and poor performance"; }
\echo   },
\echo   wal_compression: function(rowref){
\echo     val=rowref.cells[1]; val.classList.add("lime"); walcomprz = val.innerText;
\echo   },
\echo   work_mem: function(rowref){
\echo     val=rowref.cells[1];
\echo     val.title=bytesToSize(val.innerText*1024,1024) + ", Avoid global settings above 32MB to avoid memory related issues";
\echo     if(val.innerText > 98304) val.classList.add("warn");
\echo     else val.classList.add("lime");
\echo   },
\echo   bgwriter_lru_maxpages: function(rowref){
\echo     let param = params.find(p => p.param === "bgwriter_lru_maxpages");
\echo     if (typeof param["suggest"] != "undefined"){
\echo       val = val=rowref.cells[1];
\echo       val.classList.add("warn"); 
\echo       val.title="bgwriter_lru_maxpages is too low. Increase this to :" + param["suggest"];
\echo     }
\echo   },
\echo   default : function(rowref) {} 
\echo };
\echo var evalParam = function(param,rowref = null) {
\echo   if (rowref != null && rowref.id == "") rowref.id=param;  
\echo   else rowref = document.getElementById(param); 
\echo   if (paramDespatch.hasOwnProperty(param)){ 
\echo     let paramJson = {}; paramJson["param"] = param; paramJson["val"] = rowref.cells[1].innerText;
\echo     params.push(paramJson);
\echo     paramDespatch[param](rowref);
\echo    }
\echo }
\echo function checkpars(){
\echo   tab=document.getElementById("params")
\echo   tab.caption.innerHTML="<span>Parameters</span>"
\echo   trs=tab.rows
\echo   if (document.getElementById("params").rows.length > 1)
\echo     for(var i=1;i<trs.length;i++)  evalParam(trs[i].cells[0].innerText,trs[i]); 
\echo   else  strfind += "<li><b>Partial Data Collection</b></li>"
\echo  }
\echo function aged(cell){
\echo  if(cell.innerHTML > autovacuum_freeze_max_age){ cell.classList.add("warn"); cell.title =  Number(cell.innerText).toLocaleString("en-US"); }
\echo }
\echo function checktabs(){
\echo   const startTime =new Date().getTime();
\echo   tab=document.getElementById("tabInfo")
\echo   tab.caption.innerHTML="<span>Tables</span> in '" + obj.dbts.f1 + "' DB" 
\echo   const trs=document.getElementById("tabInfo").rows
\echo   const len=trs.length;
\echo   trs[0].cells[2].title="Namespace / Schema oid";trs[0].cells[3].title="Bloat in Percentage";trs[0].cells[4].title="Live Rows/Tuples";trs[0].cells[5].title="Dead Rows/Tuples";
\echo   trs[0].cells[6].title="Dead/Live ratio"; trs[0].cells[7].title="Table (main fork) size in bytes"; trs[0].cells[8].title="Total Table size (All forks + TOAST) in bytes";
\echo   trs[0].cells[9].title="Total Table size + Associated Indexes size in bytes"; 
\echo   [10,16,17].forEach(function(num){trs[0].cells[num].title="Age of unfrozen tuple. Indication of the need for VACUUM FREEZE. Current autovacuum_freeze_max_age=" + autovacuum_freeze_max_age.toLocaleString("en-US")})
\echo   trs[0].cells[18].title="Number of Blocks Read/Fetched"; trs[0].cells[19].title="Cache hit while reading";
\echo   for(var i=1;i<len;i++){
\echo     tr=trs[i]; let TotTab=tr.cells[8]; TotTabSize=Number(TotTab.innerHTML); TabInd=tr.cells[9]; TabIndSize=(TabInd.innerHTML);
\echo     if(TotTabSize > 5000000000 ) { TotTab.classList.add("lime"); TotTab.title = bytesToSize(TotTabSize) + "\nBig Table, Consider Partitioning, Archive+Purge"; 
\echo     } else TotTab.title=bytesToSize(TotTabSize);
\echo     if( TabIndSize > 2*TotTabSize && TotTabSize > 2000000 ){ TabInd.classList.add("warn"); TabInd.title="Indexes of : " + bytesToSize(TabIndSize-TotTabSize) + " is " + ((TabIndSize-TotTabSize)/TotTabSize).toFixed(2) + "x of Table " + bytesToSize(TotTabSize) + "\n Total : " + bytesToSize(TabIndSize)
\echo     } else TabInd.title=bytesToSize(TabIndSize); 
\echo     if (TabIndSize > 10000000000) TabInd.classList.add("lime");
\echo     if (tr.cells[13].innerText / obj.dbts.f4 > 12){ tr.cells[13].classList.add("warn");  tr.cells[13].title="Too frequent vacuum runs : " + Math.round(tr.cells[13].innerText / obj.dbts.f4) + "/day"; }
\echo     if (tr.cells[15].innerText > 10000) { 
\echo       tr.cells[15].title=bytesToSize(Number(tr.cells[15].innerText)); 
\echo       if (tr.cells[15].innerText > 10737418240) tr.cells[15].classList.add("warn")
\echo       else tr.cells[15].classList.add("lime")
\echo     }
\echo     aged(tr.cells[10]);
\echo     aged(tr.cells[16]);
\echo     aged(tr.cells[17]);
\echo     if (tr.cells[18].innerText / obj.dbts.f4 > 262144 ){ 
\echo       tr.cells[18].classList.add("lime"); 
\echo       tr.cells[18].title="High Utilization : " + bytesToSize(Math.round(tr.cells[18].innerText * 8192 / obj.dbts.f4)) + "/day"; 
\echo       if(tr.cells[19].innerText < 40 ){ tr.cells[19].classList.add("warn"); tr.cells[19].title="Poor cache hit ratio, Results in high DiskReads"; }
\echo       else if (tr.cells[19].innerText < 70) tr.cells[19].classList.add("lime");
\echo      }
\echo   }
\echo const endTime = new Date().getTime();
\echo console.log("time taken for checktabs :" + (endTime - startTime));
\echo }
\echo function checkdbs(){
\echo   const trs=document.getElementById("dbs").rows
\echo   const len=trs.length;
\echo   let aborts=[]; 
\echo   let strtmp=""; 
\echo   trs[0].cells[6].title="Average Temp generation Per Day"; trs[0].cells[7].title="Average Temp generation Per Day"; trs[0].cells[9].title="autovacuum_freeze_max_age=" + autovacuum_freeze_max_age.toLocaleString("en-US");
\echo   for(var i=1;i<len;i++){
\echo     tr=trs[i];
\echo     if(obj.dbts !== null && tr.cells[0].innerHTML == obj.dbts.f1) tr.cells[0].classList.add("lime");
\echo     if(tr.cells[3].innerHTML > 4000){ tr.cells[3].classList.add("warn"); tr.cells[3].title = "High number of transaction aborts/rollbacks. Please inspect PostgreSQL logs"; 
\echo      aborts.push(tr.cells[0].innerHTML)
\echo      }
\echo     [7,8].forEach(function(num) {  if (tr.cells[num].innerText > 1048576) { if(tr.cells[num].classList.length < 1) tr.cells[num].classList.add("lime"); tr.cells[num].title=bytesToSize(tr.cells[num].innerText) } });
\echo     if(tr.cells[7].innerHTML > 50000000000) {  
\echo       tr.cells[7].classList.remove("lime"); tr.cells[7].classList.add("warn"); 
\echo       let str = " temp file generation per day!. It can cause I/O performance issues." 
\echo       let param = params.find(p => p.param === "log_temp_files");
\echo       if ( param["val"] == -1 ) { 
\echo         param["suggest"] = "100"; 
\echo         str += "Consider setting log_temp_files=" + param["suggest"] + "MB to collect the problematic SQL statements to PostgreSQL logs";
\echo       }else{
\echo         str += "log_temp_files is already enabled, Analyze the PostgreSQL logs to check the problematic SQL statements";
\echo       }
\echo       evalParam("log_temp_files");
\echo       if (strtmp != "") strtmp+= ","
\echo       strtmp +=  tr.cells[7].title +"/day on "+tr.cells[0].innerHTML; 
\echo       tr.cells[7].title += str;
\echo     }
\echo     totdb=totdb+Number(tr.cells[8].innerText);
\echo     aged(tr.cells[9]);
\echo   }
\echo   if (aborts.length >0) 
\echo    strfind += "<li>High number of transaction aborts/rollbacks in databases : <b>" + aborts.toString() + "</b>, please inspect PostgreSQL logs for more details</li>" ; 
\echo   if (strtmp != "") strfind += "<li>High temp file generation : <b>" + strtmp + "</b></li>"; 
\echo }
\echo function checkextn(){
\echo   const tab=document.getElementById("tblextn");
\echo   tab.caption.innerHTML="<span>Extensions</span> in '" + obj.dbts.f1 + "' DB" 
\echo   const trs=tab.rows
\echo   const len=trs.length;
\echo   let riskyExtn=[];
\echo   for(var i=1;i<len;i++){
\echo     tr=trs[i];
\echo     if (meta.riskyExtn.includes(tr.cells[1].innerHTML)){ tr.cells[1].classList.add("warn"); tr.cells[1].title = "Risky to use in mission critical systems without support aggrement. Crashes are reported" ; }
\echo     else if (!meta.commonExtn.includes(tr.cells[1].innerHTML)) tr.cells[1].classList.add("lime");
\echo   }
\echo }
\echo function checkusers(){
\echo   tab=document.getElementById("tblusr");
\echo   tab.caption.innerHTML="<span>Users/Roles</span>  and connections"
\echo }
\echo const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;
\echo const comparer = (idx, asc) => (a, b) => ((v1, v2) =>   v1 !== '''''' && v2 !== '''''' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2))(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));
\echo document.querySelectorAll(''''th'''').forEach(th => th.addEventListener(''''click'''', (() => {
\echo   const table = th.closest(''''table'''');
\echo   th.style.cursor = "progress";
\echo   var el=document.createElement("div");
\echo   el.setAttribute("id", "cur");
\echo   if (this.asc) el.textContent = "⬆";
\echo   else el.textContent = "⬇";
\echo   th.appendChild(el);
\echo   setTimeout(() => { el.remove();},1000);
\echo   setTimeout(function (){
\echo   Array.from(table.querySelectorAll(''''tr:nth-child(n+2)'''')).sort(comparer(Array.from(th.parentNode.children).indexOf(th), this.asc = !this.asc)).forEach(tr => table.appendChild(tr) );
\echo   setTimeout(function(){th.style.cursor = "pointer";},10);
\echo   },50);
\echo })));
\echo function dbsdtls(th){
\echo   let o=JSON.parse(th.cells[1].innerText);
\echo   let str="";
\echo   if(th.cells[0].classList.contains("lime")) str = "<br/>(pg_gather connected)";
\echo   return "<b>" + th.cells[0].innerText + "</b>" + str + "<br/> Inserts per day : " + o.f1 + "<br/>Updates per day : " + o.f2 + "<br/>Deletes per day : " + o.f3 + "<br/>Stats Reset : " + o.f4 ;
\echo }
\echo function tabdtls(th){
\echo   let o=JSON.parse(th.cells[1].innerText);
\echo   let vac=th.cells[13].innerText;
\echo   let ns=obj.ns.find(el => el.nsoid === JSON.parse(th.cells[2].innerText).toString());
\echo   let str=""
\echo   if (o.f5 !== null) str += "<br/>Total Indexes: " + o.f5;
\echo   if (o.f5 !== null) str += "<br/>Unused Indexes: " + o.f6;
\echo   if (obj.dbts.f4 < 1) obj.dbts.f4 = 1;
\echo   if (vac > 0) str +="<br />Vacuums / day : " + Number(vac/obj.dbts.f4).toFixed(1);
\echo   str += "<br/>Inserts / day : " + Math.round(o.f1/obj.dbts.f4);
\echo   str += "<br/>Updates / day : " + Math.round(o.f2/obj.dbts.f4);
\echo   str += "<br/>Deletes / day : " + Math.round(o.f3/obj.dbts.f4);
\echo   str += "<br/>HOT.updates / day : " + Math.round(o.f4/obj.dbts.f4);
\echo   if (o.f2 > 0) str += "<br/>FILLFACTOR recommendation :" + Math.round(100 - 20*o.f2/(o.f2+o.f1)+ 20*o.f2*o.f4/((o.f2+o.f1)*o.f2));
\echo   if (vac/obj.dbts.f4 > 50) { 
\echo     let threshold = Math.round((Math.round(o.f2/obj.dbts.f4) + Math.round(o.f3/obj.dbts.f4))/48);
\echo     if (threshold < 500) threshold = 500;
\echo     str += "<br/>AUTOVACUUM recommendation : autovacuum_vacuum_threshold = "+ threshold +", autovacuum_analyze_threshold = " + threshold
\echo   }
\echo   return "<b>" + th.cells[0].innerText + "</b><br/>Schema : " + ns.nsname + str;
\echo }
\echo function sessdtls(th){
\echo   let o=JSON.parse(th.cells[1].innerText); let str="";
\echo   if (o.f1 !== null) str += "Database :" + o.f1 + "<br/>";
\echo   if (o.f2 !== null && o.f2.length > 1 ) str += "Application :" + o.f2 + "<br/>";
\echo   if (o.f3 !== null) str += "Client Host :" + o.f3 + "<br/>";
\echo   if (typeof o.f5 != "undefined") str += ''''<div class="warn">Victim of Blocker :'''' + o.f5 + "<div>";
\echo   if (str.length < 1) str+="Independent/Background process";
\echo   return str;
\echo }
\echo function userdtls(tr){
\echo if(tr.cells[1].innerText.length > 2){
\echo   let o=JSON.parse(tr.cells[1].innerText); let str="<b>Per DB connections</b><br>";
\echo   for(i=0;i<o.length;i++){
\echo     str += (i+1).toString() + ". Database:" + o[i].f1 + " Active:" + o[i].f2 + ", IdleInTrans:" + o[i].f3  + ", Idle:" + o[i].f4 +  " <br>";
\echo   }
\echo   return str
\echo } else return "No connections"
\echo }
\echo document.querySelectorAll(".thidden tr td:first-child").forEach(td => td.addEventListener("mouseover", (() => {
\echo   th=td.parentNode;
\echo   tab=th.closest("table");
\echo   var el=document.createElement("div");
\echo   el.setAttribute("id", "dtls");
\echo   el.setAttribute("align","left");
\echo   if(tab.id=="dbs") el.innerHTML=dbsdtls(th);
\echo   if(tab.id=="tabInfo") el.innerHTML=tabdtls(th);
\echo   if(tab.id=="tblsess") el.innerHTML=sessdtls(th);
\echo   if(tab.id=="tblusr") el.innerHTML=userdtls(th);
\echo   th.cells[2].appendChild(el);
\echo })));
\echo document.querySelectorAll(".thidden tr td:first-child").forEach(td => td.addEventListener("mouseout", (() => {
\echo   td.parentNode.cells[2].innerHTML=td.parentNode.cells[2].firstChild.textContent;
\echo })));
\echo let elem=document.getElementById("bottommenu")
\echo elem.onmouseover = function() { document.getElementById("menu").style.display = "block"; }
\echo elem.onclick = function() { document.getElementById("menu").style.display = "none"; }
\echo elem.onmouseout = function() { document.getElementById("menu").style.display = "none"; }
\echo document.querySelectorAll("#tblsess tr td:nth-child(6) , #tblstmnt tr td:nth-child(2)").forEach(td => td.addEventListener("dblclick", (() => {
\echo   if (td.title){
\echo   console.log(td.title);
\echo   navigator.clipboard.writeText(td.title).then(() => {  
\echo     var el=document.createElement("div");
\echo     el.setAttribute("id", "cur");
\echo     el.textContent = "SQL text is copied to clipboard";
\echo     td.appendChild(el);
\echo     setTimeout(() => { el.remove();},2000);
\echo    });
\echo }
\echo })));
\echo function checkindex(){
\echo tab=document.getElementById("IndInfo")
\echo tab.caption.innerHTML="<span>Indexes</span> in '" + obj.dbts.f1 + "' DB" 
\echo trs=tab.rows;
\echo for (let tr of trs) {
\echo   if(tr.cells[4].innerText == 0) {tr.cells[4].classList.add("warn"); tr.cells[4].title="Unused Index"}
\echo   tr.cells[5].title=bytesToSize(Number(tr.cells[5].innerText));
\echo   if(tr.cells[5].innerText > 2000000000) tr.cells[5].classList.add("lime");
\echo   if(tr.cells[6].innerText > 262144 && tr.cells[6].innerText/tr.cells[4].innerText > 50 ) {
\echo     if (tr.cells[4].innerText > 0 ){
\echo      tr.cells[6].title="Each Index scan had to fetch " + Math.round(tr.cells[6].innerText/tr.cells[4].innerText) + " pages on average. Expensive Index";
\echo     }else tr.cells[6].title="Unused indexes. But causing fetches without any benefit"; 
\echo     tr.cells[6].classList.add("warn");
\echo     if (tr.cells[7].innerText < 50 ){tr.cells[7].classList.add("warn");tr.cells[7].title="Poor Cache Hit";}
\echo     else if (tr.cells[7].innerText < 80 ) {tr.cells[7].classList.add("lime");tr.cells[7].title="Indexes with less cache hit can cause considerable I/O"; }
\echo   }
\echo }
\echo }
\echo tab=document.getElementById("tableConten")
\echo tab.caption.innerHTML=''''<span>DB Server Time</span> - Wait-events, CPU time and Delays (<a href="https://github.com/jobinau/pg_gather/blob/main/docs/waitevents.md">Reference</a>)''''
\echo trs=tab.rows;
\echo if (trs.length > 1){ 
\echo   maxevnt=Number(trs[1].cells[1].innerText);
\echo   for (let tr of trs) {
\echo   evnts=tr.cells[1];
\echo   if (evnts.innerText*1500/maxevnt > 1) evnts.innerHTML += ''''<div style="display:inline-block;width:'+ Number(evnts.innerText)*1500/maxevnt + 'px; border: 7px outset brown; border-width:7px 0; margin:0 5px;box-shadow: 2px 2px grey;">''''
\echo   }
\echo }else {
\echo   tab.tBodies[0].innerHTML="No Wait Event information or CPU usage information is available, Probably the PostgreSQL is completely idle or data collection failed"
\echo }
\echo function checksess(){
\echo tab=document.getElementById("tblsess")
\echo tab.caption.innerHTML=''''<span>Sessions</span>''''
\echo trs=tab.rows;
\echo for (let tr of trs){
\echo  pid=tr.cells[0]; sql=tr.cells[5]; xidage=tr.cells[8]; stime=tr.cells[10];
\echo  if(xidage.innerText > 20) xidage.classList.add("warn");
\echo  if (blokers.indexOf(Number(pid.innerText)) > -1){ pid.classList.add("high"); pid.title="Blocker"; };
\echo  if (blkvictims.indexOf(Number(pid.innerText)) > -1) { pid.classList.add("warn"); 
\echo         tr.cells[1].innerText = tr.cells[1].innerText.slice(0,-1) + '''',"f5":"' + obj.victims.find(el => el.f1 == pid.innerText).f2.toString() + '"}'''';
\echo       };
\echo  if(DurationtoSeconds(stime.innerText) > 300) stime.classList.add("warn");
\echo  if (sql.innerText.length > 10 && !sql.innerText.startsWith("**") ){ sql.title = sql.innerText; 
\echo  sql.innerText = sql.innerText.substring(0, 100); 
\echo }
\echo }}
\echo function checkstmnts(){
\echo let tab= document.getElementById("tblstmnt");
\echo tab.caption.innerHTML = "<span>Top Statements</span>"
\echo if(tab.rows.length < 2) 
\echo  tab.tBodies[0].innerHTML="No pg_stat_statements or pg_stat_monitor info found"
\echo else{
\echo  trs=tab.rows;
\echo  setTitles(trs[0],["Weighted Dense Ranking. 1 has the highest impact","SQL Statement","SQL workload / Total workload %","Number of execution of the statement",
\echo  "Avg. execution time of the statement (ms)","Average Reads (Blocks)","Cache Hit %","Avg. Dirtied Pages","Avg. Written Pages","Avg. Temp Read","Avg. Temp Write"]);
\echo   for (let tr of trs){
\echo  sql=tr.cells[1];
\echo  if (sql.innerText.length > 10 ){ sql.title = sql.innerText; sql.innerText = sql.innerText.substring(0, 100); }
\echo  let cel=tr.cells[6];
\echo  if ( cel.innerText.trim() != "" && cel.innerText < 50) cel.classList.add("warn");
\echo  cel=tr.cells[9];
\echo  if (cel.innerText > 12800) cel.classList.add("lime");
\echo  cel=tr.cells[10];
\echo  if (cel.innerText > 12800) cel.classList.add("lime");
\echo }}}
\echo function setTitles(tr,tiltes){
\echo   for(i=0;i<tiltes.length;i++) tr.cells[i].title=tiltes[i];
\echo }
\echo function checkchkpntbgwrtr(){
\echo tab=document.getElementById("tblchkpnt")
\echo tab.caption.innerHTML=''''<span>BGWriter & Checkpointer</span>''''
\echo trs=tab.rows;
\echo setTitles(trs[0],["Forced Checkpoint; Checkpoint triggered by xlog/wal; Need to adjust the max_wal_size","Average Minutes between Checkpoints","Average Write time of a checkpoint",
\echo "Average Disk sync time of a checkpoint","","","","","","","","Dirty buffers cleaned by Checkpointer","Dirty buffers cleaned by BGWriter","Dirty buffers cleaned by Session backends",
\echo "Percentage of bgwriter runs results in a halt","Percentage of bgwriter halts are due to hitting on bgwriter_lru_maxpages limit","Number of days before stats have been reset"]);
\echo if (trs.length > 1){
\echo   tr=trs[1]
\echo   if (tr.cells[0].innerText > 10){
\echo     tr.cells[0].classList.add("high"); tr.cells[0].title="More than 10% of forced checkpoints is not desirable, increase max_wal_size";
\echo   }
\echo   if(tr.cells[1].innerText < 10 ){
\echo     tr.cells[1].classList.add("high"); tr.cells[1].title="checkpoints are too frequent. consider checkpoint_timeout=1800";
\echo   }
\echo   if(tr.cells[11].innerText > 50){
\echo     tr.cells[11].classList.add("high"); tr.cells[11].title="Checkpointer is taking high load of cleaning dirty buffers";
\echo   }
\echo   if(tr.cells[13].innerText > tr.cells[12].innerText){  
\echo     tr.cells[12].classList.add("high"); tr.cells[12].title="Bgwriter should be cleaning more pages than backends.";
\echo     if (tr.cells[13].innerText > 30){ tr.cells[13].classList.add("high"); tr.cells[13].title="too many dirty pages cleaned by backends"; 
\echo     strfind += "<li>High <b>memory pressure</b>. Consider increasing RAM and shared_buffers</li>"; }  
\echo     if(tr.cells[12].innerText < 20){ 
\echo       tr.cells[12].classList.add("high"); tr.cells[12].title+="Bgwriter is not efficient";
\echo       if(tr.cells[14].innerText > 30){
\echo         tr.cells[14].classList.add("high"); tr.cells[14].title="bgwriter could run more frequently. reduce bgwriter_delay";
\echo       }
\echo       if(tr.cells[15].innerText > 10){
\echo         let param = params.find(p => p.param === "bgwriter_lru_maxpages");
\echo         param["suggest"] = Math.ceil((parseInt(param["val"]) + tr.cells[15].innerText/15*100)/100)*100;
\echo         evalParam("bgwriter_lru_maxpages");
\echo         tr.cells[15].classList.add("high"); tr.cells[15].title="bgwriter halts too frequently. increase bgwriter_lru_maxpages";
\echo       }
\echo     }
\echo   }
\echo   if (tr.cells[16].innerText.trim() == "" || tr.cells[16].innerText < 1 ){
\echo     tr.cells[16].classList.add("high"); tr.cells[16].title="sufficient bgwriter stats are not available";
\echo     document.getElementById("tblchkpnt").classList.add("high");
\echo     document.getElementById("tblchkpnt").title = "Sufficient bgwriter stats are not available. This could happen if data is collected immediately after the stats reset or a crash. At least one day of stats are required to do meaningful calculations";
\echo   }
\echo   if( tr.cells[16].innerText > 45 ){
\echo     tr.cells[16].classList.add("high"); tr.cells[16].title="Statistics of long-term avarage won't be helpful. Please consider resetting. 1 week is ideal";
\echo   }
\echo }}
\echo tab=document.getElementById("tblreplstat")
\echo tab.caption.innerHTML="<span>Replication</span>"
\echo if (tab.rows.length > 1){
\echo   for(var i=1;i<tab.rows.length;i++){
\echo     row=tab.rows[i];
\echo     [4,5,6,7,16,17].forEach(function(num){ cell=row.cells[num]; cell.title=bytesToSize(Number(cell.innerText),1024); 
\echo      if(cell.innerText > 104857600){
\echo       cell.classList.add("warn");
\echo      }else{
\echo       cell.classList.add("lime");
\echo      }
\echo     });
\echo     [14,15].forEach(function(num){  if(row.cells[num].innerText > 20) row.cells[num].classList.add("warn"); });
\echo     if (row.cells[13].innerText == "f" || row.cells[2].innerText == "") {
\echo       row.cells[8].classList.add("high");
\echo       row.cells[8].title="Abandoned replication slot";
\echo       document.getElementById("finditem").innerHTML += "<li> Abandoned replication slot : <b>" +  row.cells[8].innerText + "</b> found. This can cause unwanted WAL retention" ;
\echo     }
\echo   }
\echo }else{
\echo   tab.tBodies[0].innerHTML="No Replication data found"
\echo }
\echo document.onkeyup = function(e) {
\echo   if (e.altKey && e.which === 73) document.getElementById("topics").scrollIntoView({behavior: "smooth"});
\echo }
\echo </script>
\echo </html>
