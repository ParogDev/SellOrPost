-- luacheck for a WoW: Forever addon. Run from this folder (tools\lua.ps1 does): the generated globals list
-- lives in the scaffolding root; standalone (CI in this repo) falls back to a short list.
std = "lua51"
max_line_length = 140
codes = true
ignore = {
	"212/self", -- unused self
	"212/_.*", -- unused args named _x
	"211/_.*", -- unused locals named _x
}

local ok, wow = pcall(dofile, "../../tools/luacheck-wow-globals.lua")
if ok and type(wow) == "table" then
	read_globals = {}
	for _, g in ipairs(wow.read_globals) do
		if g ~= "SlashCmdList" then
			read_globals[#read_globals + 1] = g
		end
	end
else
	-- CI in this repo runs standalone: every global the addon touches must be here.
	read_globals = {
		"CreateFrame", "C_AddOns", "C_Item", "C_Container", "C_Timer", "GetBuildInfo", "GetTime", "WOW_PROJECT_ID",
		"issecretvalue", "date", "strtrim",
	}
end
-- FrameXML globals and other addons' APIs the generated list doesn't carry.
for _, g in ipairs({
	"DEFAULT_CHAT_FRAME", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NUM_BAG_SLOTS", "TSM_API", "Baganator",
}) do
	read_globals[#read_globals + 1] = g
end

globals = { "SellOrPost", "SellOrPostDB", "SLASH_SELLORPOST1", "SLASH_SELLORPOST2", "SlashCmdList" }

files["tests/"] = {
	std = "+busted",
	globals = {
		"SellOrPost", "SellOrPostDB", "_G", "TSM_API", "Baganator", "CreateFrame", "C_AddOns", "C_Item", "C_Container",
		"C_Timer", "GetBuildInfo", "GetTime", "WOW_PROJECT_ID", "issecretvalue", "date", "strtrim", "DEFAULT_CHAT_FRAME",
		"NUM_TOTAL_EQUIPPED_BAG_SLOTS",
	},
}
exclude_files = { ".luacheckrc", ".release/" }
