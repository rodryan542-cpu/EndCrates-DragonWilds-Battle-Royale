import unittest
from support import runtime, MATCH_MOCKS


class SchedulerScaleTests(unittest.TestCase):
    def test_fifty_simultaneous_matches_use_linear_sampling(self):
        lua=runtime();lua.execute(MATCH_MOCKS)
        lua.execute('''
            config.max_active_matches=50
            for i=5,50 do add_zone(i) end
            activate(1000)
            config.ring_enabled=true
            for _,m in pairs(engine.matches) do for id in pairs(m.alive) do
                driver.players[id].x=m.zone.center.x;driver.players[id].y=m.zone.center.y
            end end
            baseline=driver.samples
            for i=1,100 do engine:tick(clock+i) end
        ''')
        self.assertEqual(lua.eval('engine:count_matches("active")'),50)
        self.assertEqual(lua.eval('driver.samples-baseline'),100000)
        self.assertEqual(lua.eval('engine.metrics.spawn_requests'),1000)


if __name__=='__main__':
    unittest.main()
