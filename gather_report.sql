--\pset border 2
\echo <script type="text/javascript" src="http://mozigo.risko.org/js/graficarBarras.js"></script>
\echo <script type="text/javascript" src="http://mozigo.risko.org/js/tabla2array.js"></script>
\echo <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.10.2/jquery.min.js"></script>
\echo <style>
\echo table, th, td { border: 1px solid black; border-collapse: collapse; }
\echo th {background-color: #d2f2ff;}
\echo tr:nth-child(even) {background-color: #d2e2ff;}
\echo th { cursor: pointer;}
\echo </style>
\H
\echo <h2>Connection and Server</h2>
SELECT replace(connstr,'You are connected to ','') "Connection / Server info" FROM pg_srvr;
\echo <h2 id="topics">Go to Topics</h2>
\echo <ol>
\echo <li><a href="#parameters">Parameter settings</a></li>
\echo <li><a href="#findings">Important findings</a></li>
\echo <li><a href="#activiy">Session Summary</a></li>
\echo <li><a href="#time">Database time</a></li>
\echo <li><a href="#sess">Database time</a></li>
\echo </ol>
\echo <h2>Tables Info</h2>
\echo <p><b>NOTE : Rel size</b> is the  main fork size, <b>Tot.Tab size</b> includes all forks and toast, <b>Tab+Ind size</b> is tot_tab_size + all indexes</p>
SELECT c.relname "Name",c.relkind "Kind",r.relnamespace "Schema",r.blks,r.n_live_tup "Live tup",r.n_dead_tup "Dead tup",
   r.rel_size "Rel size",r.tot_tab_size "Tot.Tab size",r.tab_ind_size "Tab+Ind size",r.rel_age,r.last_vac "Last vacuum",r.last_anlyze "Last analyze",r.vac_nos,
   ct.relname "Toast name",rt.tab_ind_size "Toast+Ind" ,rt.rel_age "Toast Age",GREATEST(r.rel_age,rt.rel_age) "Max age"
  FROM pg_get_rel r
  JOIN pg_get_class c ON r.relid = c.reloid AND c.relkind <> 't'
  LEFT JOIN pg_get_toast t ON r.relid = t.relid
  LEFT JOIN pg_get_class ct ON t.toastid = ct.reloid
  LEFT JOIN pg_get_rel rt ON rt.relid = t.toastid;
\echo <a href="#topics">Go to Topics</a>
\echo <h2 id="parameters">Parameters & settings</h2>
SELECT * FROM pg_get_confs;
\echo <a href="#topics">Go to Topics</a>
\echo <h2 id="activiy">Session Summary</h2>
SELECT d.datname,state,COUNT(pid) 
  FROM pg_get_activity a LEFT JOIN pg_get_db d on a.datid = d.datid
  WHERE state is not null GROUP BY 1,2 ORDER BY 1;;
\echo <a href="#topics">Go to Topics</a>
\echo <h2 id="time">Database time</h2>
\echo <canvas id="chart" width="800" height="480" style="border: 1px solid black; float:right; width:75% ">Canvas is not supported</canvas>
\pset tableattr 'id="tableConten" name="waits"'
WITH ses AS (SELECT COUNT (*) as tot, COUNT(*) FILTER (WHERE state is not null) working FROM pg_get_activity),
    waits AS (SELECT wait_event ,count(*) cnt from pg_pid_wait group by wait_event)
  SELECT 'CPU' "Event", working*2000 - (SELECT sum(cnt) FROM waits) "Count" FROM ses
  UNION ALL
  SELECT wait_event "Event", cnt "Count" FROM waits;
--session waits
\echo <a href="#topics">Go to Topics</a>
\pset tableattr
\echo <h2 id="sess" style="clear: both">Session Timing</h2>
WITH w AS (SELECT pid,wait_event,count(*) cnt FROM pg_pid_wait GROUP BY 1,2 ORDER BY 1,2)
SELECT a.pid,2000 - s.tot cpu,string_agg( w.wait_event ||':'|| w.cnt,',') waits FROM pg_get_activity a 
    JOIN w ON a.pid = w.pid
    JOIN (SELECT pid,sum(cnt) tot FROM w GROUP BY 1) s ON a.pid = s.pid
WHERE a.state IS NOT NULL
GROUP BY 1,2;
\echo <a href="#topics">Go to Topics</a>
\echo <h2 id="findings" style="clear: both">Important Findings</h2>
\echo <a href="#topics">Go to Topics</a>
\echo <script type="text/javascript">
\echo  const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;
\echo  const comparer = (idx, asc) => (a, b) => ((v1, v2) =>   v1 !== '''''' && v2 !== '''''' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2))(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));
\echo  document.querySelectorAll(''''th'''').forEach(th => th.addEventListener(''''click'''', (() => {
\echo      const table = th.closest(''''table'''');
\echo      Array.from(table.querySelectorAll(''''tr:nth-child(n+2)''''))
\echo          .sort(comparer(Array.from(th.parentNode.children).indexOf(th), this.asc = !this.asc))
\echo          .forEach(tr => table.appendChild(tr) );
\echo  })));
\echo  </script>
\echo <script type="text/javascript">
\echo $(''''<thead></thead>'''').prependTo(''''#tableConten'''').append($(''''#tableConten tr:first''''));
\echo  var misParam ={ miMargen : 0.80, separZonas : 0.05, tituloGraf : "Database Time", tituloEjeX : "Event",  tituloEjeY : "Count", nLineasDiv : 10,
\echo  mysColores :[
\echo                ["rgba(93,18,18,1)","rgba(196,19,24,1)"],  //red
\echo                ["rgba(171,115,51,1)","rgba(251,163,1,1)"], //yellow
\echo              ],
\echo     anchoLinea : 2, };
\echo    obtener_datos_tabla_convertir_en_array(''''tableConten'''',graficarBarras,''''chart'''',''''750'''',''''480'''',misParam,true);
\echo </script>
  
