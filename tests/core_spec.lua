local mock = require("tests.wow_mock")

describe("Core", function()
	local ns
	local function cb(link)
		return mock.plugins.sellorpost.callback(0, 1, 123, link)
	end

	before_each(function()
		mock.install()
	end)

	describe("with Baganator and TSM loaded", function()
		before_each(function()
			ns = mock.loadAddon(".")
		end)

		it("registers a Baganator junk plugin", function()
			assert.is_table(mock.plugins.sellorpost)
			assert.equal("registered", ns.selftest.plugin)
		end)

		it("marks what the post rule refuses and keeps what posts", function()
			local cheap = mock.item(
				"|Hcheap|h",
				{ name = "Linen", quality = 1, sellPrice = 13, group = "Materials`Cloth", post = 0 }
			)
			local good = mock.item(
				"|Hgood|h",
				{ name = "Silk", quality = 1, sellPrice = 38, group = "Materials`Cloth", post = 900 }
			)
			assert.is_true(cb(cheap))
			assert.is_false(cb(good))
		end)

		it("never marks the Keep group", function()
			local pot = mock.item(
				"|Hpot|h",
				{ name = "Potion", quality = 1, sellPrice = 10, group = "Keep (never post)", post = 0 }
			)
			assert.is_false(cb(pot))
		end)

		it("caches a verdict until the TTL runs out", function()
			local l = mock.item("|Hx|h", { name = "X", quality = 1, sellPrice = 5, group = "Bags", post = 0 })
			cb(l)
			cb(l)
			assert.equal(1, mock.priceCalls)
			assert.equal(1, ns.counters.cacheHits)
			mock.clock = mock.clock + ns.CACHE_TTL
			cb(l)
			assert.equal(2, mock.priceCalls)
		end)

		it("does not cache an item the client has not loaded yet", function()
			assert.is_false(cb("|Hlater|h"))
			assert.equal(1, ns.counters.notNow)
			mock.item("|Hlater|h", { name = "Later", quality = 0, sellPrice = 4 })
			assert.is_true(cb("|Hlater|h"))
		end)

		it("skips secret links", function()
			local l = mock.item("|Hs|h", { name = "S", quality = 0, sellPrice = 4 })
			mock.secret[l] = true
			assert.is_false(cb(l))
			assert.equal(0, ns.counters.checked)
		end)

		it("names the broken link when the post source is missing", function()
			local l = mock.item("|Hb|h", { name = "B", quality = 1, sellPrice = 5, group = "Bags" })
			assert.is_false(cb(l))
			assert.equal(1, ns.counters.broken)
			assert.matches("is the `post` custom source defined", ns.selftest.lastBroken.reason, 1, true)
		end)

		it("does not cache a broken verdict and warns once per session", function()
			local l = mock.item("|Hb|h", { name = "B", quality = 1, sellPrice = 5, group = "Bags" })
			cb(l)
			cb(l)
			assert.equal(2, mock.priceCalls)
			assert.equal(1, #mock.chat)
			assert.matches("can't judge items, nothing is marked", mock.chat[1], 1, true)
			mock.items[l].post = 0
			assert.is_true(cb(l))
		end)

		it("keeps a grey item in a held group", function()
			local g = mock.item("|Hhg|h", { name = "HG", quality = 0, sellPrice = 3, group = "Keep (never post)" })
			assert.is_false(cb(g))
			assert.equal(0, mock.priceCalls)
		end)

		it("redraws the bags once when items judged 'not now' load", function()
			cb("|Hlate1|h")
			cb("|Hlate2|h")
			mock.fire("GET_ITEM_INFO_RECEIVED", 1)
			mock.fire("GET_ITEM_INFO_RECEIVED", 2)
			assert.equal(2, #mock.timers) -- the login refresh and one redraw
			mock.timers[2].fn()
			assert.equal(1, mock.refreshes)
			mock.fire("GET_ITEM_INFO_RECEIVED", 3)
			assert.equal(2, #mock.timers) -- nothing waiting any more
		end)

		it("counts stacks it could not judge yet in /sellorpost", function()
			mock.bags[0] = { [1] = { link = "|Hunknown|h", count = 1 } }
			SlashCmdList.SELLORPOST("")
			assert.matches("nothing in the bags to vendor", mock.chat[1], 1, true)
			assert.matches("1 stacks not judged yet", mock.chat[2], 1, true)
		end)

		it("refuses a rule for a group TSM does not have and suggests the spelling", function()
			mock.item("|Hk|h", { name = "K", quality = 1, sellPrice = 5, group = "Materials`Leather", post = 0 })
			SlashCmdList.SELLORPOST("rule materials`leather off")
			assert.is_nil(_G.SellOrPostDB.rules["materials`leather"])
			assert.matches("did you mean 'Materials`Leather'", mock.chat[1], 1, true)
		end)

		it("lists rules sorted and tagged", function()
			mock.item("|Hc|h", { name = "C", quality = 1, sellPrice = 5, group = "Bags", post = 0 })
			SlashCmdList.SELLORPOST("rule Bags off")
			mock.chat = {}
			SlashCmdList.SELLORPOST("rules")
			assert.equal("  Bags: off (saved)", mock.chat[2])
			assert.equal("  Keep (never post): off (default)", mock.chat[3])
		end)

		it("survives a TSM error", function()
			local l = mock.item("|He|h", { name = "E", quality = 1, sellPrice = 5, group = "Bags", post = "error" })
			assert.is_false(cb(l))
			assert.matches("GetCustomPriceValue failed", ns.selftest.lastBroken.reason, 1, true)
			assert.is_nil(ns.selftest.lastError)
		end)

		it("writes the selftest with the code's version", function()
			local st = ns.selftest.snapshot("logout")
			assert.equal(ns.VERSION, st.version)
			assert.is_true(st.pluginActive)
			assert.is_true(st.tsmLoaded)
			assert.equal(st, _G.SellOrPostDB.selftest)
		end)

		it("refreshes the bags after login so early verdicts are dropped", function()
			assert.equal(1, #mock.timers)
			local l = mock.item("|Hy|h", { name = "Y", quality = 0, sellPrice = 4 })
			cb(l)
			mock.timers[1].fn()
			assert.equal(1, mock.refreshes)
			assert.is_nil(ns.cache[l])
		end)

		it("lists what to vendor with /sellorpost", function()
			local a = mock.item("|Ha|h", { name = "A", quality = 0, sellPrice = 10 })
			local b = mock.item("|Hb2|h", { name = "B2", quality = 1, sellPrice = 50, group = "Bags", post = 5000 })
			mock.bags[0] = { [1] = { link = a, count = 3 }, [2] = { link = b, count = 1 } }
			SlashCmdList.SELLORPOST("")
			assert.matches("1 stacks to vendor, 30c", mock.chat[1], 1, true)
			assert.matches("|Ha|h x3", mock.chat[2], 1, true)
		end)

		it("changes a group rule with /sellorpost rule and saves it", function()
			local l =
				mock.item("|Hk|h", { name = "K", quality = 1, sellPrice = 5, group = "Materials`Leather", post = 0 })
			assert.is_false(cb(l))
			SlashCmdList.SELLORPOST("rule Materials`Leather on")
			assert.is_true(_G.SellOrPostDB.rules["Materials`Leather"])
			assert.is_true(cb(l))
			SlashCmdList.SELLORPOST("rule Materials`Leather default")
			assert.is_nil(_G.SellOrPostDB.rules["Materials`Leather"])
			assert.is_false(cb(l))
		end)
	end)

	it("reports TSM missing as broken for grouped-looking items, still marks greys", function()
		mock.tsmLoaded = false
		ns = mock.loadAddon(".")
		local grey = mock.item("|Hg|h", { name = "G", quality = 0, sellPrice = 2 })
		local white = mock.item("|Hw|h", { name = "W", quality = 1, sellPrice = 2 })
		assert.is_true(cb(grey))
		assert.is_false(cb(white))
		assert.matches("TradeSkillMaster not loaded", ns.selftest.lastBroken.reason, 1, true)
	end)

	it("loads without Baganator and says so", function()
		mock.baganatorLoaded = false
		ns = mock.loadAddon(".")
		assert.matches("Baganator not loaded", ns.selftest.plugin, 1, true)
		assert.is_false(ns.pluginActive())
	end)
end)
