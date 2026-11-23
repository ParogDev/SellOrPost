-- Addon entry: the Baganator junk plugin, the TSM lookups behind it, the selftest contract (docs/verify-loop.md in
-- the scaffolding) and /sellorpost. It only reads TSM: nothing here mails, posts or sells.
local ADDON, ns = ...

SellOrPost = ns

local Logic = ns.Logic

ns.VERSION = "0.1.0"
ns.PLUGIN_ID = "sellorpost"
ns.PLUGIN_LABEL = "SellOrPost (TSM post rule)"
-- A verdict is reused this long (seconds of GetTime) before TSM is asked again: prices move with scans, slowly.
ns.CACHE_TTL = 120

local DB_VERSION = 1

local counters = { checked = 0, junk = 0, cacheHits = 0, broken = 0, notNow = 0 }
local selftest = { counters = counters, recent = {} }
ns.counters = counters
ns.selftest = selftest

local cache = {}
ns.cache = cache

function ns.initDB(saved)
	local db = type(saved) == "table" and saved or {}
	db.dbVersion = db.dbVersion or DB_VERSION
	db.rules = type(db.rules) == "table" and db.rules or {}
	db.selftest = db.selftest or {}
	ns.db = db
	SellOrPostDB = db
	ns.rules = Logic.mergeRules(Logic.DEFAULT_RULES, db.rules)
	return db
end

local function version()
	local ok, v = pcall(C_AddOns.GetAddOnMetadata, ADDON, "Version")
	if not ok or type(v) ~= "string" or v:find("@", 1, true) then
		return ns.VERSION
	end
	return v
end
ns.version = version

local function now()
	return date("%Y-%m-%d %H:%M:%S")
end

local function guard(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		selftest.lastError = { where = where, error = tostring(err), at = now() }
	end
	return ok, err
end

-- ---------------------------------------------------------------------------------------------------------
-- The verdict for one item link
-- ---------------------------------------------------------------------------------------------------------

-- The inputs Logic.verdict needs, or nil and the link that broke ("not now" when the client has not cached the item).
local function gather(itemLink)
	local name, _, quality, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemLink)
	if not name then
		return nil, "not now: item info not cached yet"
	end
	local item = { name = name, quality = quality, sellPrice = sellPrice }
	if not item.sellPrice or item.sellPrice <= 0 then
		return item -- Logic decides without TSM
	end
	-- A grey still needs its group (a held group wins over "poor quality") but never the post price.
	local grey = quality == 0
	local function broken(msg)
		if not grey then
			item.groupPath = "?" -- reach the post check so the broken link is reported
			item.postError = msg
		end
		return item
	end
	if type(TSM_API) ~= "table" then
		return broken("TradeSkillMaster not loaded")
	end
	local okS, itemString = pcall(TSM_API.ToItemString, itemLink)
	if not okS or not itemString then
		return broken("TSM_API.ToItemString failed: " .. tostring(itemString))
	end
	local okG, path = pcall(TSM_API.GetGroupPathByItem, itemString)
	if not okG then
		return broken("TSM_API.GetGroupPathByItem failed: " .. tostring(path))
	end
	item.groupPath = path
	if not path or grey then
		return item
	end
	local okP, value, err = pcall(TSM_API.GetCustomPriceValue, Logic.POST_STRING, itemString)
	if not okP then
		item.postError = "TSM_API.GetCustomPriceValue failed: " .. tostring(value)
	elseif type(value) == "number" then
		item.post = value
	else
		item.postError = "TSM gave no value for '"
			.. Logic.POST_STRING
			.. "' (is the `post` custom source defined?)"
			.. (err and (": " .. tostring(err)) or "")
	end
	return item
end

local function remember(entry)
	local recent = selftest.recent
	recent[#recent + 1] = entry
	if #recent > 20 then
		table.remove(recent, 1)
	end
end

local function say(line)
	DEFAULT_CHAT_FRAME:AddMessage(line)
end

-- Returns junk (boolean), the reason, and the vendor price per item (nil when the item is not loaded yet).
-- A "not now" or "broken:" verdict is never cached: the next bag redraw asks again.
function ns.evaluate(itemLink)
	local t = GetTime()
	local hit = cache[itemLink]
	if hit and t - hit.at < ns.CACHE_TTL then
		counters.cacheHits = counters.cacheHits + 1
		return hit.junk, hit.reason, hit.sellPrice
	end
	counters.checked = counters.checked + 1
	local item, why = gather(itemLink)
	if not item then
		counters.notNow = counters.notNow + 1
		ns.waitingForItems = true -- GET_ITEM_INFO_RECEIVED redraws the bags
		return false, why
	end
	local junk, reason = Logic.verdict(item, ns.rules)
	if reason:sub(1, 7) == "broken:" then
		counters.broken = counters.broken + 1
		selftest.lastBroken = { item = item.name, reason = reason, at = now() }
		if not ns.warned then
			ns.warned = true
			say("SellOrPost: can't judge items, nothing is marked (" .. reason:sub(9) .. "). /sellorpost for details.")
		end
		return false, reason, item.sellPrice
	end
	if junk then
		counters.junk = counters.junk + 1
	end
	cache[itemLink] = { at = t, junk = junk, reason = reason, sellPrice = item.sellPrice }
	remember({ item = item.name, group = item.groupPath, post = item.post, junk = junk, reason = reason })
	return junk, reason, item.sellPrice
end

-- Baganator's callback: function(bagID, slotID, itemID, itemLink) -> true when the item is junk.
function ns.junkCallback(_, _, _, itemLink)
	if type(itemLink) ~= "string" or issecretvalue(itemLink) then
		return false
	end
	local ok, junk = guard("evaluate", ns.evaluate, itemLink)
	return ok and junk == true
end

function ns.clearCache()
	for k in pairs(cache) do
		cache[k] = nil
	end
end

local function refreshBags()
	ns.clearCache()
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
end
ns.refreshBags = refreshBags

local function registerPlugin()
	if not (Baganator and Baganator.API and Baganator.API.RegisterJunkPlugin) then
		selftest.plugin = "Baganator not loaded: nothing to mark"
		return
	end
	Baganator.API.RegisterJunkPlugin(ns.PLUGIN_LABEL, ns.PLUGIN_ID, ns.junkCallback)
	selftest.plugin = "registered"
end
ns.registerPlugin = registerPlugin

local function pluginActive()
	if not (Baganator and Baganator.API and Baganator.API.IsJunkPluginActive) then
		return false
	end
	local ok, active = pcall(Baganator.API.IsJunkPluginActive, ns.PLUGIN_ID)
	return ok and active == true
end
ns.pluginActive = pluginActive

-- ---------------------------------------------------------------------------------------------------------
-- selftest
-- ---------------------------------------------------------------------------------------------------------
function selftest.snapshot(phase)
	local okB, buildVersion, buildNumber, _, interface = pcall(GetBuildInfo)
	ns.db.selftest = {
		phase = phase,
		version = version(),
		build = okB and (tostring(buildVersion) .. "." .. tostring(buildNumber)) or "GetBuildInfo failed",
		interface = okB and interface or nil,
		project = WOW_PROJECT_ID,
		loadedAt = selftest.loadedAt,
		savedAt = now(),
		plugin = selftest.plugin,
		pluginActive = pluginActive(),
		tsmLoaded = type(TSM_API) == "table",
		postString = Logic.POST_STRING,
		rules = ns.rules,
		counters = counters,
		recent = selftest.recent,
		lastBroken = selftest.lastBroken,
		lastError = selftest.lastError,
	}
	return ns.db.selftest
end

-- ---------------------------------------------------------------------------------------------------------
-- /sellorpost
-- ---------------------------------------------------------------------------------------------------------
-- Every stack in the bags that the plugin marks, with its vendor value, and how many stacks could not be judged
-- yet (item info not loaded).
function ns.scanBags()
	local out, total, unresolved = {}, 0, 0
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink
			if link and not issecretvalue(link) then
				local junk, reason, sellPrice = ns.evaluate(link)
				if not sellPrice then
					unresolved = unresolved + 1
				elseif junk then
					local value = sellPrice * (info.stackCount or 1)
					total = total + value
					out[#out + 1] = { link = link, count = info.stackCount or 1, value = value, reason = reason }
				end
			end
		end
	end
	return out, total, unresolved
end

-- Whether a typed rule path names a TSM group (or a parent of one), and the TSM spelling when only case differs.
local function knownGroup(path)
	if type(TSM_API) ~= "table" then
		return true -- cannot check; do not nag
	end
	local ok, paths = pcall(TSM_API.GetGroupPaths, {})
	if not ok or type(paths) ~= "table" then
		return true
	end
	local lower = path:lower()
	for _, p in ipairs(paths) do
		if p == path or p:sub(1, #path + 1) == path .. "`" then
			return true
		end
		if p:lower() == lower then
			return false, p
		end
	end
	return false
end

function ns.slash(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "refresh" then
		refreshBags()
		say("SellOrPost: verdicts cleared, bags refreshed.")
	elseif cmd == "rule" then
		local path, value = rest:match("^(.-)%s+(%S+)$")
		if not path or path == "" or not (value == "on" or value == "off" or value == "default") then
			say("SellOrPost: /sellorpost rule <TSM group path, subgroups joined by `> on|off|default")
			return
		end
		if value ~= "default" then
			local known, spelled = knownGroup(path)
			if not known then
				say(
					"SellOrPost: no TSM group is called '"
						.. path
						.. "'"
						.. (spelled and (" (did you mean '" .. spelled .. "'?)") or "")
						.. "; rule not saved."
				)
				return
			end
		end
		if value == "default" then
			ns.db.rules[path] = nil
		else
			ns.db.rules[path] = value == "on"
		end
		ns.rules = Logic.mergeRules(Logic.DEFAULT_RULES, ns.db.rules)
		refreshBags()
		say(string.format("SellOrPost: %s is now %s.", path, value))
	elseif cmd == "rules" then
		say("SellOrPost group rules (off = never marked; longest match wins):")
		local paths = {}
		for path in pairs(ns.rules) do
			paths[#paths + 1] = path
		end
		table.sort(paths)
		for _, path in ipairs(paths) do
			local saved = ns.db.rules[path] ~= nil and "saved" or "default"
			say(string.format("  %s: %s (%s)", path, ns.rules[path] and "on" or "off", saved))
		end
	else
		if not pluginActive() then
			say(
				"SellOrPost: not the active Baganator junk plugin. Pick it under Plugins > Junk detection in Baganator's settings."
			)
		end
		local items, total, unresolved = ns.scanBags()
		if #items == 0 then
			say("SellOrPost: nothing in the bags to vendor.")
		else
			say(string.format("SellOrPost: %d stacks to vendor, %s at the vendor:", #items, Logic.money(total)))
			for _, it in ipairs(items) do
				say(string.format("  %s x%d  %s  (%s)", it.link, it.count, Logic.money(it.value), it.reason))
			end
		end
		if unresolved > 0 then
			say(string.format("SellOrPost: %d stacks not judged yet (item info loading); run it again.", unresolved))
		end
		if selftest.lastBroken then
			say("SellOrPost: last failure: " .. selftest.lastBroken.reason)
		end
		say("  /sellorpost rules | rule <group> on|off|default | refresh")
	end
end

SLASH_SELLORPOST1 = "/sellorpost"
SLASH_SELLORPOST2 = "/sop"
SlashCmdList.SELLORPOST = function(msg)
	guard("slash", ns.slash, msg)
	if selftest.lastError and selftest.lastError.where == "slash" then
		say("SellOrPost error: " .. selftest.lastError.error)
		selftest.lastError = nil
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			ns.initDB(SellOrPostDB)
			guard("registerPlugin", registerPlugin)
		end
	elseif event == "PLAYER_LOGIN" then
		selftest.loadedAt = now()
		guard("snapshot", selftest.snapshot, "login")
		-- TSM fills its price data after login; verdicts made before then are thrown away
		C_Timer.After(10, function()
			guard("refresh", refreshBags)
		end)
	elseif event == "PLAYER_LOGOUT" then
		guard("snapshot", selftest.snapshot, "logout")
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- items judged "not now" have loaded: one redraw a second at most, however many items arrive
		if ns.waitingForItems and not ns.refreshQueued then
			ns.refreshQueued = true
			C_Timer.After(1, function()
				ns.refreshQueued = false
				ns.waitingForItems = false
				guard("refresh", refreshBags)
			end)
		end
	end
end)
