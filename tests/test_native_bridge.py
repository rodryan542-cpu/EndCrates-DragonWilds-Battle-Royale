import unittest
from support import runtime
from native_support import NATIVE_MOCKS


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.lua=runtime();self.lua.execute(NATIVE_MOCKS)
        self.lua.execute("config=require('config');Adapter=require('adapter');adapter=Adapter.new(config,print);adapter:refresh();id=adapter:identify(pc1)")

    def test_server_peer_identity_comes_from_player_state(self):
        self.assertTrue(self.lua.eval('id:match("^owner1:")~=nil'))

    def test_non_authority_player_is_not_registered(self):
        self.lua.execute('pc1.authority=false;result=adapter:identify(pc1)')
        self.assertIsNone(self.lua.globals().result)

    def test_mode_and_release_restore_pvp_and_lock_state(self):
        self.lua.execute("adapter:mode(id,'active')")
        self.assertTrue(self.lua.eval('pc1.Pawn.damage.bIsPvpEnabled'))
        self.assertTrue(self.lua.eval('pc1.Pawn.health.immortal'))
        self.lua.execute('adapter:release(id)')
        self.assertFalse(self.lua.eval('pc1.Pawn.damage.bIsPvpEnabled'))
        self.assertFalse(self.lua.eval('pc1.Pawn.health.immortal'))

    def test_protection_locker_is_unique_shared_and_inert(self):
        self.lua.execute("adapter:mode(id,'lobby');adapter:mode(adapter:identify(pc2),'lobby')")
        self.assertEqual(self.lua.eval('game_state.created_components'),1)
        self.assertFalse(self.lua.eval('adapter.locker.ticking'))
        self.assertFalse(self.lua.eval('pc1.Pawn.health.locker==pc1'))
        self.assertTrue(self.lua.eval('pc1.Pawn.health.locker==pc2.Pawn.health.locker'))

    def test_actor_lookup_uses_address_not_lua_wrapper_identity(self):
        self.lua.execute("wrapper=object('Another Lua wrapper');wrapper.GetAddress=function()return pc1.Pawn:GetAddress()end")
        self.assertEqual(self.lua.eval('adapter:actor_id(wrapper)'),self.lua.globals().id)

    def test_refresh_does_not_release_locks_for_new_wrappers_of_same_pawn(self):
        self.lua.execute("adapter:mode(id,'lobby');original=pc1.Pawn;wrapper=setmetatable({GetAddress=original.GetAddress},{__index=original});pc1.Pawn=wrapper;adapter:refresh()")
        self.assertTrue(self.lua.eval('original.health.immortal'))

    def test_native_teleports_are_globally_staggered_and_deduplicated(self):
        self.lua.execute("for n=3,20 do make_pc(n) end;adapter:refresh();for pid in pairs(adapter.peers) do adapter:teleport(pid,{x=100,y=200,z=300});adapter:teleport(pid,{x=400,y=500,z=600}) end;adapter:pump_teleports()")
        self.assertEqual(self.lua.eval('adapter.teleports_sent'),4)
        self.lua.execute('for i=1,5 do adapter:pump_teleports() end')
        self.assertEqual(self.lua.eval('adapter.teleports_sent'),20)
        self.assertEqual(self.lua.eval('pc1.Pawn.location.X'),400)

    def test_pending_or_refused_teleport_prevents_ready_state(self):
        self.lua.execute('adapter:teleport(id,{x=100,y=200,z=300})')
        self.assertFalse(self.lua.eval('adapter:snapshot(id).ready'))
        self.lua.execute('pc1.Pawn.refuse_teleport=true;adapter:pump_teleports()')
        self.assertFalse(self.lua.eval('adapter:snapshot(id).ready'))

    def test_loading_screen_prevents_ready_state(self):
        self.lua.execute('pc1.Pawn.teleporting=true')
        self.assertFalse(self.lua.eval('adapter:snapshot(id).ready'))

    def test_cancelled_work_cannot_teleport_after_stop(self):
        self.lua.execute('adapter:teleport(id,{x=100,y=200,z=300});adapter:cancel_work();adapter:pump_teleports()')
        self.assertIsNone(self.lua.eval('pc1.Pawn.teleport_calls'))

    def test_preflight_checks_capacity_pvp_and_world_pin(self):
        self.assertFalse(self.lua.eval('(adapter:preflight())'))
        self.lua.execute('config.pvp_world_confirmed=true;config.world_id=adapter:world_id()')
        self.assertTrue(self.lua.eval('(adapter:preflight())'))
        self.lua.execute('session.MaxPlayers=6')
        self.assertFalse(self.lua.eval('(adapter:preflight())'))
        self.lua.execute('session.MaxPlayers=100;config.world_id="other_world"')
        self.assertFalse(self.lua.eval('(adapter:preflight())'))

    def test_message_queue_is_bounded(self):
        self.lua.execute('config.max_pending_messages=10;for i=1,30 do adapter:message(id,"test") end')
        self.assertEqual(self.lua.eval('#adapter.messages'),10)
        self.assertEqual(self.lua.eval('adapter.dropped_messages'),20)
        self.lua.execute('adapter:flush_messages()')
        self.assertEqual(self.lua.eval('#delivered'),8)

    def test_native_owner_id_controls_admin_access(self):
        self.assertFalse(self.lua.eval('adapter:is_admin(id)'))
        self.assertTrue(self.lua.eval('adapter:is_admin(adapter:identify(pc2))'))


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.lua=runtime();self.lua.execute(NATIVE_MOCKS)

    def boot(self):
        self.lua.execute("require('main');loop()")

    def test_startup_is_passive_without_configured_arenas(self):
        self.boot()
        self.assertIsNone(self.lua.eval('pc1.Pawn.health.immortal'))
        self.assertIsNone(self.lua.eval('pc1.Pawn.teleport_calls'))

    def test_chat_command_is_consumed_and_replied_to_its_owner(self):
        self.boot();self.lua.execute("chat_command(pc1,'!brhelp');loop()")
        self.assertEqual(self.lua.eval('packet.MessageBody'),'')
        self.assertEqual(self.lua.eval('#delivered'),1)
        self.assertEqual(self.lua.eval('delivered[1].owner'),'owner1')

    def test_normal_chat_is_unchanged(self):
        self.boot();self.lua.execute("chat_command(pc1,'hello');loop()")
        self.assertEqual(self.lua.eval('packet.MessageBody'),'hello')
        self.assertEqual(self.lua.eval('#delivered'),0)

    def test_spoofed_sender_data_does_not_grant_admin(self):
        self.boot();self.lua.execute("chat_command(pc1,'!br enable',{PlayerId=2,PrimaryNetId=pc2.PlayerState.UniqueId});loop()")
        self.assertIn('restricted',self.lua.eval('delivered[1].data.MessageBody'))
        self.assertFalse(self.lua.eval("require('config').enabled"))

    def test_remote_client_does_not_intercept_server_commands(self):
        self.boot();self.lua.execute("pc1.authority=false;chat_command(pc1,'!ffa');loop()")
        self.assertEqual(self.lua.eval('packet.MessageBody'),'!ffa')

    def test_missing_native_function_fails_closed(self):
        self.lua.execute("missing_function='/Script/Dominion.HealthComponent:SetIsImmortal'")
        self.boot()
        self.assertEqual(self.lua.eval("hooks['/Script/JagexChatBackend.PlayerChatComponent:Server_SendChatMessage']==nil"),True)
        self.assertIsNone(self.lua.eval('pc1.Pawn.health.immortal'))

    def test_commands_and_chat_queue_are_rate_limited(self):
        self.boot();self.lua.execute("for i=1,20 do chat_command(pc1,'!brhelp') end;loop()")
        self.assertEqual(self.lua.eval('#delivered'),3)

    def test_game_thread_callbacks_do_not_overlap(self):
        self.boot();self.lua.execute('scheduled=0;ExecuteInGameThread=function(fn)scheduled=scheduled+1;held=fn end;loop();loop()')
        self.assertEqual(self.lua.eval('scheduled'),1)


if __name__=='__main__':
    unittest.main()
