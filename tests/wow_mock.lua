-- Minimal WoW client globals so the addon loads under busted, plus scriptable items, bags, TSM_API and Baganator.
-- Dumb tables, not a client; the real check is the in-game reload.
local M = {}

local function newFrame()
	local f = { _events = {} }
	function f:RegisterEvent(e)
		self._events[e] = true
	end
	function f:SetScript(k, fn)
		self["_" .. k] = fn
	end
	M.frames[#M.frames + 1] = f
	return f
end

function M.install()
	M.frames = {}
	M.clock = 1000
	M.secret = {}
	M.chat = {}
	M.timers = {}
	-- link -> { name, quality, sellPrice, group, post }; post may be a number, nil, or "error"
	M.items = {}
	M.bags = {} -- [bag][slot] = { link, count }
	M.tsmLoaded = true
	M.plugins = {}
	M.refreshes = 0
	M.activePlugin = "sellorpost"
	M.baganatorLoaded = true
	M.priceCalls = 0

	_G.CreateFrame = newFrame
	_G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, line)
			M.chat[#M.chat + 1] = line
		end,
	}
	_G.SlashCmdList = {}
	_G.WOW_PROJECT_ID = 18
	_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
	_G.GetBuildInfo = function()
		return "1.60.1", "70790", "Nov 4 2026", 16001
	end
	_G.C_AddOns = {
		GetAddOnMetadata = function()
			return "@project-version@"
		end,
	}
	_G.date = function(fmt)
		return os.date(fmt)
	end
	_G.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	_G.issecretvalue = function(v)
		return v ~= nil and M.secret[v] == true
	end
	_G.GetTime = function()
		return M.clock
	end
	_G.C_Timer = {
		After = function(sec, fn)
			M.timers[#M.timers + 1] = { sec = sec, fn = fn }
		end,
	}
	_G.C_Item = {
		GetItemInfo = function(link)
			local it = M.items[link]
			if not it then
				return nil
			end
			return it.name, link, it.quality, 10, 1, "Trade Goods", "Other", 20, "", 1, it.sellPrice
		end,
	}
	_G.C_Container = {
		GetContainerNumSlots = function(bag)
			return M.bags[bag] and 16 or 0
		end,
		GetContainerItemInfo = function(bag, slot)
			local s = M.bags[bag] and M.bags[bag][slot]
			if not s then
				return nil
			end
			return { hyperlink = s.link, stackCount = s.count }
		end,
	}
	_G.TSM_API = {
		ToItemString = function(link)
			return M.items[link] and ("i:" .. M.items[link].name) or nil
		end,
		GetGroupPathByItem = function(itemString)
			for _, it in pairs(M.items) do
				if "i:" .. it.name == itemString then
					return it.group
				end
			end
		end,
		GetCustomPriceValue = function(str, itemString)
			M.priceCalls = M.priceCalls + 1
			assert(str == "first(post, 0.001)", "unexpected price string " .. str)
			for _, it in pairs(M.items) do
				if "i:" .. it.name == itemString then
					if it.post == "error" then
						error("TSM blew up")
					end
					if it.post == nil then
						return nil, "Invalid price source: post"
					end
					return it.post
				end
			end
		end,
	}
	_G.Baganator = {
		API = {
			RegisterJunkPlugin = function(label, id, cb)
				M.plugins[id] = { label = label, callback = cb }
			end,
			IsJunkPluginActive = function(id)
				return M.activePlugin == id
			end,
			RequestItemButtonsRefresh = function()
				M.refreshes = M.refreshes + 1
			end,
		},
	}
end

function M.loadAddon(dir, saved)
	if not M.tsmLoaded then
		_G.TSM_API = nil
	end
	if not M.baganatorLoaded then
		_G.Baganator = nil
	end
	local ns = {}
	for _, f in ipairs({ "Logic.lua", "Core.lua" }) do
		local chunk, err = loadfile(dir .. "/" .. f)
		assert(chunk, err)
		chunk("SellOrPost", ns)
	end
	_G.SellOrPostDB = saved
	M.fire("ADDON_LOADED", "SellOrPost")
	M.fire("PLAYER_LOGIN")
	M.ns = ns
	return ns
end

function M.fire(event, ...)
	for _, f in ipairs(M.frames) do
		if f._OnEvent and f._events[event] then
			f._OnEvent(f, event, ...)
		end
	end
end

function M.item(link, fields)
	M.items[link] = fields
	return link
end

return M
