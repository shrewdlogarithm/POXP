extends Control

onready var logln = RegEx.new()
onready var zoned = RegEx.new()
onready var cmds = RegEx.new()

var optfile = "poxp-settings.json"
var logfile = "poxp-log.txt"
var clientlogfile = "/Client.txt"

var lastch = ""
var lastchlvl = 0

var options = {}
var profileURL = "https://www.pathofexile.com/character-window/get-characters?realm=pc&accountName="
var xpthresh = [0,525,1760,3781,7184,12186,19324,29377,43181,61693,85990,117506,157384,207736,269997,346462,439268,
551295,685171,843709,1030734,1249629,1504995,1800847,2142652,2535122,2984677,3496798,4080655,4742836,5490247,6334393,
7283446,8384398,9541110,10874351,12361842,14018289,15859432,17905634,20171471,22679999,25456123,28517857,31897771,
35621447,39721017,44225461,49176560,54607467,60565335,67094245,74247659,82075627,90631041,99984974,110197515,121340161,
133497202,146749362,161191120,176922628,194049893,212684946,232956711,255001620,278952403,304972236,333233648,363906163,
397194041,433312945,472476370,514937180,560961898,610815862,664824416,723298169,786612664,855129128,929261318,1009443795,
1096169525,1189918242,1291270350,1400795257,1519130326,1646943474,1784977296,1934009687,2094900291,2268549086,2455921256,
2658074992,2876116901,3111280300,3364828162,3638186694,3932818530,4250334444]

func _ready():	
	logln.compile("^([0-9]{4})/([0-9]{2})/([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) ([0-9]+?) (.*)$")
	#zoned.compile("You have entered (.*)\\.")
	zoned.compile("Generating level ([0-9]+) area \"(.*)\"")

	$HTTPRequest.connect("request_completed", self, "loadProfileDone")
	
	loadoptions()
	if options.has("logd"):
		find_node("lblLogf").text = options["logd"]
	if options.has("acct"):
		find_node("leAccount").text = options["acct"]
	
	$Timer.wait_time = 5
	$Timer.one_shot = false
	$Timer.start()
	
	addOut("Scanning started...")
	checklog(true)
	liveloadProfile()

var lastclip
func _process(elaps):
	var clip = OS.get_clipboard()
	if clip != lastclip:
		lastclip = clip
		# TODO process for map data
		
func _on_Timer_timeout():
	if checklog():
		liveloadProfile()	
	
var lastmod = 0
func checklog(first = false):
	var f = File.new()
	var tochk = false
	if options.has("logd") and options["logd"] != "":
		var logf = options["logd"] + clientlogfile
		if !f.file_exists(logf):
			addOut(logf + "not found")
		else:
			var mod = f.get_modified_time(logf)
			if mod != lastmod:
				var lldate = []
				f.open(logf,File.READ)
				f.seek_end(-65535) # limit how many lines we check
				while not f.eof_reached():
					var ln = f.get_line()
					var loglnf = logln.search(ln)
					if loglnf:
						var newlog = false
						if options.has("lldate"):
							for dp in range(1,8):
								if int(loglnf.strings[dp]) > int(options["lldate"][dp]):
									newlog = true
									break
								elif int(loglnf.strings[dp]) < int(options["lldate"][dp]):
									break
						if newlog and !first:
							# TODO check our chat - capture commands here?
							for chr in options["profile"]:
								cmds.compile(" " + chr["name"] + ": (.*)")
								var cmdsf = cmds.search(loglnf.strings[8])
								if cmdsf:
									addOut(cmdsf.strings[1])
							var zonedf = zoned.search(loglnf.strings[8])
							# TODO show XP penalty for this zone??
							if zonedf:
								addOut(zonedf.strings[2] + " (" + zonedf.strings[1] + ")")
								tochk = true
						lldate = loglnf.strings
				options["lldate"] = lldate
				f.close()
				saveoptions()
	return tochk

func liveloadProfile():
	if !options.has("acct") or  options["acct"] == "":
		addOut("Enter Account Name")
	else:
		var error = $HTTPRequest.request(profileURL + options["acct"])
		if error != OK:
			addOut("HTTP: Error " + error)
		
func loadProfileDone(result, response_code, headers, body):
	var response = JSON.parse(body.get_string_from_utf8())
	if response_code == 200:
		if options.has("profile"):
			checkchars(options["profile"],response.result)
		options["profile"] = response.result
		saveoptions()
	else:
		addOut("HTTP: Response " + str(response_code) + " Check Account Name?")

func getlvlprog(lvl,xp):
	var totlvl = xpthresh[int(lvl)] - xpthresh[int(lvl)-1]
	var sofarlvl = int(xp) - int(xpthresh[int(lvl)-1])
	return "L%s %s" % [lvl,str(int(sofarlvl/(totlvl/100)))+"%"]

func checkchars(prevdb,db):
	for chr in db:
		for ochr in prevdb:
			if ochr["name"] == chr["name"] and chr["experience"] != ochr["experience"]:
				addOut("%s From %s -> %s" % [chr["name"],getlvlprog(ochr["level"],ochr["experience"]),getlvlprog(chr["level"],chr["experience"])])
	for chr in db:
		if "lastActive" in chr and lastch != chr["name"]:
			lastch = chr["name"]
			lastchlvl = chr["level"]
			addOut("Last Active " + lastch + "(" + str(lastchlvl) + ")")
			break;
	
func _on_btnLogf_pressed():
	var dlg = find_node("dlgLogf")
	if options.has("logd") and options["logd"] != "":
		dlg.set_current_path(options["logd"] + "/") # trailing slash required to work
	dlg.popup()
		
func _on_dlgLogf_dir_selected(dir):
	find_node("lblLogf").text = dir
	options["logd"] = dir
	saveoptions()
	if !File.new().file_exists(dir + clientlogfile):
		addOut("Log file not found at " + dir + clientlogfile)

func _on_leAccount_text_changed(new_text):
	if new_text != "":
		options["acct"] = new_text
		saveoptions()

func _on_btnAccount_pressed():
	if find_node("leAccount").text != "":
		$Timer.stop()
		checklog()
		liveloadProfile()
		$Timer.start()

func addOut(ln):
	var dt = OS.get_time()
	var te = find_node("teOutp")
	te.cursor_set_line(te.get_line_count())
	var op = "%02d:%02d:%02d %s" % [dt["hour"],dt["minute"],dt["second"],ln]
	te.insert_text_at_cursor(op + "\n")
	var f = File.new()
	f.open(logfile,File.READ_WRITE)
	f.seek_end()
	f.store_line(op)
	f.close()

func loadoptions():
	var f = File.new()
	if f.file_exists(optfile):
		f.open(optfile,File.READ)
		var res = JSON.parse(f.get_as_text())
		if !res.error:
			options = res.result
		f.close()
	
func saveoptions():
	var f = File.new()
	f.open(optfile,File.WRITE)
	f.store_string(JSON.print(options))
	f.close()
