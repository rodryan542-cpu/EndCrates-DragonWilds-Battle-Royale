import unittest
from support import runtime, MATCH_MOCKS


class RoundFeatures(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()
        self.lua.execute(MATCH_MOCKS)

    def run_lua(self, source):
        self.lua.execute(source)

    def test_circle_interpolates_and_stops_at_final_radius(self):
        self.run_lua('''config.ring_enabled=true;R=require('ring')
            a=R.at(config,config.zones[1],120);b=R.at(config,config.zones[1],180)
            c=R.at(config,config.zones[1],240);d=R.at(config,config.zones[1],100000)''')
        self.assertEqual(self.lua.eval('a.phase'), 'closing')
        self.assertEqual(self.lua.eval('a.radius'), 12000)
        self.assertAlmostEqual(self.lua.eval('b.radius'), 9600)
        self.assertEqual(self.lua.eval('c.phase'), 'holding')
        self.assertAlmostEqual(self.lua.eval('c.radius'), 7200)
        self.assertEqual(self.lua.eval('d.phase'), 'final')
        self.assertAlmostEqual(self.lua.eval('d.radius'), 720)

    def test_bad_ring_settings_fail_before_any_match(self):
        for source in ('config.ring_stages[2].factor=0.9',
                       'config.ring_stages[1].shrink=0',
                       'config.ring_stages[1].factor=0/0',
                       'config.ring_stages={}',
                       'config.ring_stages[3].factor=0'):
            lua = runtime();lua.execute(MATCH_MOCKS)
            lua.execute(source+';ok=pcall(G.validate,config,false)')
            self.assertFalse(lua.globals().ok)

    def test_shrinking_circle_eliminates_campers_after_grace(self):
        self.run_lua('''config.ring_enabled=true;config.ring_stages={{hold=2,shrink=2,factor=0.1}}
            activate(20);engine:tick(clock+4)''')
        self.assertEqual(self.lua.eval('engine.matches[1].alive_count'), 20)
        self.run_lua('engine:tick(clock+14)')
        self.assertEqual(self.lua.eval('engine.metrics.draws'), 1)

    def test_reentering_shrinking_circle_clears_grace(self):
        self.run_lua('''config.ring_enabled=true;config.ring_stages={{hold=2,shrink=2,factor=0.1}}
            activate(20);engine:tick(clock+4)
            driver.players.p1.x=100000;driver.players.p1.y=100000;engine:tick(clock+5);engine:tick(clock+14)''')
        self.assertEqual(self.lua.eval('engine.metrics.wins'), 1)
        self.assertEqual(self.lua.eval('engine.peers.p1.stats.wins'), 1)

    def test_rings_use_independent_round_clocks(self):
        self.run_lua('config.ring_enabled=true;activate(40)')
        self.assertNotEqual(self.lua.eval('engine.matches[1].started_at'), self.lua.eval('engine.matches[2].started_at'))
        self.run_lua('''local m=engine.matches[1];local n=engine.matches[2];local R=require('ring')
            first=R.at(config,m.zone,180);second=R.at(config,n.zone,180-(n.started_at-m.started_at))''')
        self.assertLess(self.lua.eval('first.radius'), self.lua.eval('second.radius'))

    def test_leaver_is_not_requeued_when_start_is_cancelled(self):
        self.run_lua('join(1,20);queue(1,20);engine:tick(1);engine.peers.p1.autoqueue=true;engine:leave("p1",2);engine:tick(3)')
        self.assertEqual(self.lua.eval('#engine.queue'), 19)
        self.assertIsNone(self.lua.eval('engine:queue_position("p1")'))
        self.assertFalse(self.lua.eval('engine.peers.p1.autoqueue'))

    def test_tied_knockouts_share_place_and_only_commit_stats_once(self):
        self.run_lua('activate(20);for n=1,19 do driver.players["p"..n].health=1 end;engine:tick(clock+1);engine:tick(clock+2)')
        self.assertEqual(self.lua.eval('engine.peers.p1.stats.last'), 2)
        self.assertEqual(self.lua.eval('engine.peers.p19.stats.last'), 2)
        self.assertEqual(self.lua.eval('engine.peers.p20.stats.last'), 1)
        self.assertEqual(self.lua.eval('engine.peers.p20.stats.wins'), 1)
        self.assertEqual(self.lua.eval('engine.peers.p20.stats.rounds'), 1)
        self.assertEqual(self.lua.eval('#engine.recent[1].rows'), 20)

    def test_native_and_health_knockouts_are_deduplicated(self):
        self.run_lua('''activate(20);driver.players.p1.health=1;before=#driver.calls
            engine:tick(clock+1,{{id='p1',reason='native death'},{id='p1',reason='native death'}})''')
        self.assertEqual(self.lua.eval('engine.matches[1].alive_count'), 19)
        self.assertEqual(self.lua.eval('#driver.calls-before'), 2)  # protect, then teleport once
        self.assertEqual(self.lua.eval('engine.matches[1].results.p1.reason'), 'native death')

    def test_native_death_at_countdown_deadline_cancels_before_combat(self):
        self.run_lua('''join(1,20);queue(1,20);for t=0,4 do engine:tick(t)end
            engine:tick(engine.matches[1].starts_at,{{id='p1',reason='native death'}})''')
        self.assertEqual(self.lua.eval('engine:count_matches()'),0)
        self.assertEqual(self.lua.eval('engine.metrics.wins'),0)
        self.assertEqual(self.lua.eval('engine.peers.p1.stats.rounds'),0)

    def test_native_and_sampled_knockouts_in_last_two_players_are_a_draw(self):
        self.run_lua('''activate(20);for n=1,18 do engine:eliminate('p'..n,'test',clock+1)end
            driver.players.p20.health=1;engine:tick(clock+2,{{id='p19',reason='native death'}})''')
        self.assertEqual(self.lua.eval('engine.metrics.draws'),1)
        self.assertEqual(self.lua.eval('engine.metrics.wins'),0)
        self.assertEqual(self.lua.eval('engine.peers.p19.stats.last'),1)
        self.assertEqual(self.lua.eval('engine.peers.p20.stats.last'),1)

    def test_full_wipe_never_awards_a_win_in_standings(self):
        self.run_lua('activate(20);for n=1,20 do driver.players["p"..n].health=1 end;engine:tick(clock+1)')
        self.assertEqual(self.lua.eval('engine.peers.p1.stats.wins'), 0)
        self.assertTrue(self.lua.eval('engine.recent[1].draw'))

    def test_cancellation_does_not_count_as_played_round(self):
        self.run_lua('activate(20);engine:cancel(1,"admin",clock+1,false)')
        self.assertEqual(self.lua.eval('engine.peers.p1.stats.rounds'), 0)
        self.assertEqual(self.lua.eval('#engine.recent'), 0)

    def test_autoqueue_waits_for_lobby_arrival(self):
        self.run_lua('''activate(20);engine.peers.p1.autoqueue=true;driver.auto_teleport=false
            engine:eliminate('p1','test',clock+1);engine:tick(clock+2)''')
        self.assertEqual(self.lua.eval('#engine.queue'), 0)
        self.run_lua('driver.players.p1.x=0;driver.players.p1.y=0;engine:tick(clock+3)')
        self.assertEqual(self.lua.eval('engine:queue_position("p1")'), 1)

    def test_batch_feed_avoids_one_broadcast_per_knockout(self):
        self.run_lua('activate(20);for n=1,19 do driver.players["p"..n].health=1 end;engine:tick(clock+1)')
        self.assertEqual(self.lua.eval('messages_containing("Out:")'), 20)
        self.assertEqual(self.lua.eval('messages_containing("Eliminated:")'), 19)

    def test_history_is_bounded_and_other_rounds_keep_running(self):
        self.run_lua('config.result_history=1;activate(40);for n=1,19 do driver.players["p"..n].health=1 end;engine:tick(clock+1)')
        self.assertEqual(self.lua.eval('engine.matches[2].alive_count'), 20)
        self.run_lua('for n=21,39 do driver.players["p"..n].health=1 end;engine:tick(clock+2)')
        self.assertEqual(self.lua.eval('#engine.recent'), 1)
        self.assertEqual(self.lua.eval('engine.recent[1].id'), 2)


if __name__ == '__main__':
    unittest.main()
