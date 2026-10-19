import unittest
from support import runtime, MATCH_MOCKS


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.lua=runtime();self.lua.execute(MATCH_MOCKS)
        self.lua.execute('''
            Commands=require('commands');join(1,1)
            function driver:is_admin()return self.admin==true end
            function driver:preflight()return true end
            function driver:world_id()return 'world' end
            catalogue={given=0}
            function catalogue:give(_,id,query,count)self.given=self.given+count;return count,query end
            function catalogue:refresh_loaded()end
            function catalogue:find()return {} end
            commands=Commands.new(engine,driver,catalogue)
            function command(line)commands:run('p1',line,1)end
            function last_message()return driver.messages[#driver.messages].text end
        ''')

    def test_give_in_lobby_uses_validated_count(self):
        self.lua.execute("command('!give Scimitar_Dragon 2')")
        self.assertEqual(self.lua.eval('catalogue.given'),2)

    def test_invalid_count_does_not_reach_inventory(self):
        for count in ('-1','0','10000','1.5','1e309'):
            self.lua.globals().bad_command='!give Scimitar_Dragon '+count
            self.lua.execute('command(bad_command)')
            self.assertEqual(self.lua.eval('catalogue.given'),0)

    def test_active_match_rejects_item_grants(self):
        self.lua.execute("engine.peers.p1.state='active';command('!give Scimitar_Dragon 1')")
        self.assertEqual(self.lua.eval('catalogue.given'),0)

    def test_queued_players_can_finish_their_kits(self):
        self.lua.execute("queue(1,1);command('!give Scimitar_Dragon 1')")
        self.assertEqual(self.lua.eval('catalogue.given'),1)

    def test_lobby_location_is_required(self):
        self.lua.execute("driver.players.p1.x=100000;command('!give Scimitar_Dragon 1')")
        self.assertEqual(self.lua.eval('catalogue.given'),0)

    def test_unconfigured_mod_cannot_grant_items(self):
        self.lua.execute("config.enabled=false;command('!give Scimitar_Dragon 1')")
        self.assertEqual(self.lua.eval('catalogue.given'),0)

    def test_non_admin_cannot_enable_or_edit_the_mod(self):
        self.lua.execute("config.enabled=false;command('!br enable')")
        self.assertFalse(self.lua.eval('config.enabled'))
        self.assertIn('restricted',self.lua.eval('last_message()'))

    def test_geometry_cannot_be_changed_during_play(self):
        self.lua.execute("driver.admin=true;command('!br lobby 2000')")
        self.assertEqual(self.lua.eval('config.lobby.radius'),1500)

    def test_duplicate_spawn_is_rejected(self):
        self.lua.execute("driver.admin=true;config.enabled=false;local p=config.zones[1].spawns[1];driver.players.p1.x=p.x;driver.players.p1.y=p.y;driver.players.p1.z=p.z;command('!br spawn zone1')")
        self.assertEqual(self.lua.eval('#config.zones[1].spawns'),20)

    def test_rate_limits_are_per_player(self):
        self.lua.execute("a=commands:allowed('a',0);b=commands:allowed('a',0);c=commands:allowed('a',0);d=commands:allowed('a',0);other=commands:allowed('b',0);reset=commands:allowed('a',2)")
        self.assertFalse(self.lua.globals().d)
        self.assertTrue(self.lua.globals().other)
        self.assertTrue(self.lua.globals().reset)


if __name__=='__main__':
    unittest.main()
