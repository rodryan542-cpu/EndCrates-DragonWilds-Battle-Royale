import unittest
from support import runtime, MATCH_MOCKS


class PlayerFeatures(unittest.TestCase):
    def setUp(self):
        self.lua=runtime();self.lua.execute(MATCH_MOCKS)
        self.lua.execute('''
            join(1,2);catalogue={calls={},stock={}}
            function catalogue:unique(name)assert(name~='ambiguous','Several items match.');return {name=name}end
            function catalogue:topup(adapter,id,name,count)
                self.calls[#self.calls+1]={id=id,name=name}
                local key=id..name;local missing=math.max(0,count-(self.stock[key] or 0));self.stock[key]=(self.stock[key] or 0)+missing
                return missing,name,missing
            end
            function driver:is_admin()return true end
            commands=require('commands').new(engine,driver,catalogue)
            function command(text,id)commands:run(id or 'p1',text,1)end
            function last()return driver.messages[#driver.messages].text end
        ''')

    def test_new_commands_are_intercepted_but_regular_chat_is_not(self):
        for name in ('kit','ring','queue','autoqueue','stats','top','results','matches'):
            self.assertTrue(self.lua.eval(f'commands:handles("!{name}")'))
        self.assertFalse(self.lua.eval('commands:handles("hello")'))

    def test_queue_position_reports_fifo_position(self):
        self.lua.execute('queue(1,2);command("!queue","p2")')
        self.assertIn('Position 2 of 2', self.lua.eval('last()'))

    def test_kit_load_is_budgeted_and_does_not_duplicate_existing_stock(self):
        self.lua.execute('command("!kit add Sword 1");command("!kit add Food 20");command("!kit load");commands:pump_kits()')
        self.assertEqual(self.lua.eval('#catalogue.calls'), 1)
        self.assertTrue(self.lua.eval('engine.peers.p1.kit_loading'))
        self.lua.execute('commands:pump_kits();command("!kit load");commands:pump_kits();commands:pump_kits()')
        self.assertEqual(self.lua.eval('catalogue.stock.p1Food'), 20)
        self.assertIsNone(self.lua.eval('engine.peers.p1.kit_loading'))

    def test_kit_loader_rotates_players(self):
        self.lua.execute('''command('!kit add Sword 1');command('!kit add Food 20');command('!kit load')
            command('!kit add Bow 1','p2');command('!kit load','p2');commands:pump_kits();commands:pump_kits()''')
        self.assertEqual(self.lua.eval('catalogue.calls[2].id'), 'p2')

    def test_cannot_queue_until_kit_load_finishes(self):
        self.lua.execute('command("!kit add Food 20");command("!kit load");command("!ffa")')
        self.assertEqual(self.lua.eval('#engine.queue'), 0)
        self.lua.execute('commands:pump_kits();command("!ffa")')
        self.assertEqual(self.lua.eval('#engine.queue'), 1)

    def test_kit_load_rejects_combat_and_stops_after_leaving_lobby(self):
        self.lua.execute('command("!kit add Sword 1");command("!kit load");driver.players.p1.x=99999;commands:pump_kits()')
        self.assertEqual(self.lua.eval('#catalogue.calls'), 0)
        self.assertIsNone(self.lua.eval('engine.peers.p1.kit_loading'))
        self.lua.execute('engine.peers.p1.state="active";command("!kit load")')
        self.assertIsNone(self.lua.eval('commands.kit_jobs.p1'))

    def test_kit_load_cannot_cross_character_reload(self):
        self.lua.execute('command("!kit add Sword 1");command("!kit load");engine.peers.p1.token="replacement";commands:pump_kits()')
        self.assertEqual(self.lua.eval('#catalogue.calls'), 0)

    def test_kit_edits_update_counts_remove_and_clear_without_grants(self):
        self.lua.execute('command("!kit add Food 20");command("!kit add Food 30")')
        self.assertEqual(self.lua.eval('#engine.peers.p1.kit'), 1)
        self.assertEqual(self.lua.eval('engine.peers.p1.kit[1].count'), 30)
        self.lua.execute('command("!kit remove Food");command("!kit add Sword 1");command("!kit clear")')
        self.assertEqual(self.lua.eval('#engine.peers.p1.kit'), 0)
        self.assertEqual(self.lua.eval('#catalogue.calls'), 0)

    def test_kit_rejects_bad_counts_ambiguous_names_and_thirteenth_entry(self):
        self.lua.execute('command("!kit add Food -1");command("!kit add ambiguous 2")')
        self.assertEqual(self.lua.eval('#engine.peers.p1.kit'), 0)
        self.lua.execute('for n=1,13 do command("!kit add Item"..n.." 1") end')
        self.assertEqual(self.lua.eval('#engine.peers.p1.kit'), 12)

    def test_queued_player_cannot_begin_kit_load(self):
        self.lua.execute('command("!kit add Food 20");queue(1,1);command("!kit load")')
        self.assertIsNone(self.lua.eval('commands.kit_jobs'))

    def test_autoqueue_has_explicit_values_and_lobby_turns_it_off(self):
        self.lua.execute('command("!autoqueue yes")')
        self.assertIsNone(self.lua.eval('engine.peers.p1.autoqueue'))
        self.lua.execute('command("!autoqueue on");command("!lobby")')
        self.assertFalse(self.lua.eval('engine.peers.p1.autoqueue'))

    def test_arena_editor_removes_specific_spawn_and_zone_only_while_disabled(self):
        self.lua.execute('command("!br removespawn zone1 3")')
        self.assertEqual(self.lua.eval('#config.zones[1].spawns'), 20)
        self.lua.execute('config.enabled=false;command("!br removespawn zone1 3");command("!br removezone zone2")')
        self.assertEqual(self.lua.eval('#config.zones[1].spawns'), 19)
        self.assertEqual(self.lua.eval('#config.zones'), 3)
        self.assertEqual(self.lua.eval('config.zones[2].id'), 'zone3')

    def test_match_browser_and_circle_report_current_round(self):
        self.lua.execute('activate(40);command("!matches")')
        self.assertIn('#1 zone1: active',self.lua.eval('last()'))
        self.assertIn('#2 zone2: active',self.lua.eval('last()'))
        self.lua.execute('command("!ring")')
        self.assertIn('Center X=100000 Y=100000',self.lua.eval('last()'))
        self.assertIn('radius=12000',self.lua.eval('last()'))

    def test_finished_round_has_private_result_pages_stats_and_leaderboard(self):
        self.lua.execute('activate(20);for n=1,19 do driver.players["p"..n].health=1 end;engine:tick(clock+1);command("!results","p20")')
        self.assertIn('#1 Player 20',self.lua.eval('last()'))
        self.lua.execute('command("!results 2","p20")')
        self.assertIn('(page 2/2)',self.lua.eval('last()'))
        self.lua.execute('command("!stats","p20")')
        self.assertIn('1 wins',self.lua.eval('last()'))
        self.lua.execute('command("!top")')
        self.assertTrue(self.lua.eval('last()').startswith('1. Player 20'))

    def test_failed_kit_load_stops_remaining_items_without_requeue_lock(self):
        self.lua.execute('''command('!kit add Sword 1');command('!kit add Food 10');command('!kit load')
            catalogue.topup=function()error('Unavailable asset')end;commands:pump_kits()''')
        self.assertIsNone(self.lua.eval('commands.kit_jobs.p1'))
        self.assertIsNone(self.lua.eval('engine.peers.p1.kit_loading'))
        self.assertIn('Unavailable asset',self.lua.eval('last()'))


if __name__ == '__main__':
    unittest.main()
