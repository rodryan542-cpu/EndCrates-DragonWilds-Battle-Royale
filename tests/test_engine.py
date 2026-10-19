import unittest
from support import runtime, MATCH_MOCKS


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.lua=runtime();self.lua.execute(MATCH_MOCKS)

    def execute(self, code):
        self.lua.execute(code)

    def value(self, code):
        return self.lua.eval(code)

    def test_nineteen_wait_twentieth_starts(self):
        self.execute('join(1,19);queue(1,19);engine:tick(1)')
        self.assertEqual(self.value('engine:count_matches()'),0)
        self.execute('join(20,20);queue(20,20);engine:tick(2)')
        self.assertEqual(self.value('engine:count_matches()'),1)
        self.assertEqual(self.value('#engine.matches[1].order'),20)

    def test_duplicate_queue_and_leave(self):
        self.execute('join(1,1);queue(1,1);accepted=engine:enqueue("p1",0)')
        self.assertFalse(self.value('accepted'));self.assertEqual(self.value('#engine.queue'),1)
        self.execute('engine:leave("p1",0)');self.assertEqual(self.value('#engine.queue'),0)

    def test_two_simultaneous_matches_and_fifo_spillover(self):
        self.execute('activate(41)')
        self.assertEqual(self.value('engine:count_matches("active")'),2)
        self.assertEqual(self.value('#engine.queue'),1)
        self.assertEqual(self.value('engine.queue[1]'),'p41')
        self.assertNotEqual(self.value('engine.matches[1].zone.id'),self.value('engine.matches[2].zone.id'))
        self.assertEqual(self.value('engine.matches[1].order[1]'),'p1')
        self.assertEqual(self.value('engine.matches[2].order[1]'),'p21')

    def test_match_capacity_and_busy_zone_are_respected(self):
        self.execute('config.max_active_matches=1;activate(40)')
        self.assertEqual(self.value('engine:count_matches()'),1)
        self.assertEqual(self.value('#engine.queue'),20)
        self.execute('config.max_active_matches=4;config.zones={config.zones[1]};engine:tick(clock+1)')
        self.assertEqual(self.value('engine:count_matches()'),1)

    def test_spawn_work_has_a_global_budget(self):
        self.execute('config.max_loading_matches=4;join(1,80);queue(1,80)')
        for now in range(12):
            before=self.value('engine.metrics.spawn_requests')
            self.execute(f'engine:tick({now})')
            self.assertLessEqual(self.value('engine.metrics.spawn_requests')-before,4)

    def test_distinct_recorded_spawn_points(self):
        self.execute('activate(20);seen={};for id,p in pairs(engine.matches[1].targets) do local key=p.x..":"..p.y;assert(not seen[key]);seen[key]=true end')
        self.assertEqual(self.value('engine.matches[1].alive_count'),20)

    def test_no_start_before_teleport_arrival(self):
        self.execute('join(1,20);queue(1,20);driver.auto_teleport=false;for t=0,20 do engine:tick(t) end')
        self.assertEqual(self.value('engine.matches[1].phase'),'loading')
        self.assertFalse(self.value('engine:can_damage("p1","p2")'))

    def test_loading_failure_cancels_without_a_winner(self):
        self.execute('join(1,20);queue(1,20);driver.auto_teleport=false;engine:tick(0);engine:tick(91)')
        self.assertEqual(self.value('engine:count_matches()'),0)
        self.assertEqual(self.value('engine.metrics.wins'),0)

    def test_refused_teleport_cancels_group(self):
        self.execute('join(1,20);queue(1,20);driver.teleport_ok=false;engine:tick(1)')
        self.assertEqual(self.value('engine:count_matches()'),0)

    def test_failed_protection_never_starts_combat(self):
        self.execute('join(1,20);queue(1,20);driver.mode_ok=false;engine:tick(1)')
        self.assertEqual(self.value('engine:count_matches()'),0)

    def test_countdown_protects_players(self):
        self.execute('join(1,20);queue(1,20);for t=0,4 do engine:tick(t) end')
        self.assertEqual(self.value('engine.matches[1].phase'),'countdown')
        self.assertFalse(self.value('engine:can_damage("p1","p2")'))

    def test_combat_permission_same_match_only(self):
        self.execute('activate(40)')
        self.assertTrue(self.value('engine:can_damage("p1","p2")'))
        self.assertFalse(self.value('engine:can_damage("p1","p21")'))
        self.assertFalse(self.value('engine:can_damage(nil,"p1")'))

    def test_unmanaged_players_preserve_native_permission(self):
        self.execute('config.enabled=false;join(1,2)')
        self.assertIsNone(self.value('engine:can_damage("p1","p2")'))

    def test_nineteen_knockouts_award_one_winner_once(self):
        self.execute('activate(20);for n=1,19 do driver.players["p"..n].health=1 end;engine:tick(clock+1)')
        self.assertEqual(self.value('engine.metrics.wins'),1)
        self.assertEqual(self.value('messages_containing("VICTOR:")'),20)
        self.assertEqual(self.value('engine:count_matches()'),0)
        self.execute('engine:tick(clock+2)');self.assertEqual(self.value('engine.metrics.wins'),1)

    def test_simultaneous_full_wipe_is_a_draw(self):
        self.execute('activate(20);for n=1,20 do driver.players["p"..n].health=0 end;engine:tick(clock+1)')
        self.assertEqual(self.value('engine.metrics.wins'),0)
        self.assertEqual(self.value('engine.metrics.draws'),1)
        self.assertEqual(self.value('messages_containing("VICTOR:")'),0)

    def test_disconnect_and_reconnect_cannot_rejoin_match(self):
        self.execute('activate(20);engine:disconnect("p1",clock+1);engine:register("p1","Player 1","new_pawn",clock+2)')
        self.assertIsNone(self.value('engine.peers.p1.match'))
        self.assertFalse(self.value('engine.matches[1].alive.p1==true'))

    def test_disconnect_during_loading_cancels_and_returns_others(self):
        self.execute('join(1,20);queue(1,20);engine:tick(0);engine:disconnect("p1",1)')
        self.assertEqual(self.value('engine:count_matches()'),0)
        self.assertFalse(self.value('engine.peers.p1.connected'))
        self.assertIsNone(self.value('engine.peers.p1.requeue'))

    def test_boundary_grace_resets_after_reentering(self):
        self.execute('activate(20);driver.players.p1.x=999999;engine:tick(clock+1)')
        self.assertIsNotNone(self.value('engine.peers.p1.match'))
        self.execute('driver.players.p1.x=100000;engine:tick(clock+5);driver.players.p1.x=999999;engine:tick(clock+6);engine:tick(clock+15)')
        self.assertIsNotNone(self.value('engine.peers.p1.match'))
        self.execute('engine:tick(clock+16)');self.assertIsNone(self.value('engine.peers.p1.match'))

    def test_replaced_pawn_is_eliminated(self):
        self.execute('activate(20);driver.players.p1.token="replacement";engine:tick(clock+1)')
        self.assertIsNone(self.value('engine.peers.p1.match'))

    def test_return_timeout_locks_queue(self):
        self.execute('activate(20);driver.auto_teleport=false;engine:eliminate("p1","test",clock+1);engine:tick(clock+200);accepted=engine:enqueue("p1",clock+201)')
        self.assertEqual(self.value('engine.peers.p1.state'),'return_failed')
        self.assertFalse(self.value('accepted'))

    def test_default_round_has_no_forced_time_limit(self):
        self.execute('activate(20);engine:tick(clock+100000)')
        self.assertEqual(self.value('engine:count_matches()'),1)

    def test_optional_time_limit_is_a_draw(self):
        self.execute('config.match_timeout=2;activate(20);engine:tick(clock+3)')
        self.assertEqual(self.value('engine.metrics.draws'),1)

    def test_shutdown_releases_all_players_and_stops_admission(self):
        self.execute('activate(41);engine:shutdown(clock+1)')
        self.assertEqual(self.value('engine:count_matches()'),0)
        self.assertEqual(self.value('#engine.queue'),0)
        self.assertEqual(self.value('engine.peers.p1.state'),'unmanaged')
        self.assertIsNone(self.value('engine:can_damage("p1","p2")'))

    def test_bad_or_overlapping_geometry_is_rejected(self):
        self.execute('config.zones[2].center=G.copy(config.zones[1].center);ok=pcall(G.validate,config,true)')
        self.assertFalse(self.value('ok'))

    def test_missing_spawn_is_rejected(self):
        self.execute('table.remove(config.zones[1].spawns);ok=pcall(G.validate,config,true)')
        self.assertFalse(self.value('ok'))

    def test_accidental_non_twenty_player_config_is_rejected(self):
        self.execute('config.players_per_match=19;ok=pcall(G.validate,config,false)')
        self.assertFalse(self.value('ok'))

    def test_idle_disconnected_peers_are_evicted(self):
        self.execute('join(1,1);engine:disconnect("p1",1);engine:tick(1000)')
        self.assertIsNone(self.value('engine.peers.p1'))

    def test_clock_moving_back_does_not_reverse_timers(self):
        self.execute('engine:tick(100);engine:tick(5)')
        self.assertEqual(self.value('engine.last_now'),100)

    def test_invalid_snapshot_cannot_crash_combat_loop(self):
        self.execute('activate(20);driver.players.p1.x=nil;engine:tick(clock+1)')
        self.assertIsNone(self.value('engine.peers.p1.match'))


if __name__=='__main__':
    unittest.main()
