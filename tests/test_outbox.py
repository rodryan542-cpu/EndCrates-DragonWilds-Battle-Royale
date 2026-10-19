import unittest
from support import runtime
from native_support import NATIVE_MOCKS


class OutboxTests(unittest.TestCase):
    def setUp(self):
        self.lua=runtime();self.lua.execute("q=require('outbox').new(3)")

    def test_critical_notices_bypass_search_replies(self):
        self.lua.execute("q:push({id='a',text='items'});q:push({id='b',text='fight',priority=true});first=q:pop(0);second=q:pop(0)")
        self.assertEqual(self.lua.eval('first.text'),'fight')
        self.assertEqual(self.lua.eval('second.text'),'items')

    def test_full_queue_discards_normal_before_critical(self):
        self.lua.execute("q:push({id='a',text='win',priority=true});q:push({id='a',text='old'});q:push({id='a',text='new'});q:push({id='a',text='last'})")
        self.assertEqual(self.lua.eval('q.count'),3)
        self.assertEqual(self.lua.eval('q:pop(0).text'),'win')
        self.assertEqual(self.lua.eval('q:pop(0).text'),'new')
        self.assertEqual(self.lua.eval('q.dropped'),1)

    def test_normal_traffic_cannot_displace_a_full_critical_queue(self):
        self.lua.execute("for i=1,3 do q:push({id='a',text='win'..i,priority=true})end;accepted=q:push({id='a',text='items'})")
        self.assertFalse(self.lua.globals().accepted)
        self.assertEqual(self.lua.eval('q:pop(0).text'),'win1')

    def test_expired_countdowns_are_not_delivered_late(self):
        self.lua.execute("q:push({id='a',text='5 seconds',priority=true,expires=5});q:push({id='a',text='win',priority=true});result=q:pop(6)")
        self.assertEqual(self.lua.eval('result.text'),'win')
        self.assertEqual(self.lua.eval('q.count'),0)

    def test_coalescing_is_per_player_and_replaces_message_priority(self):
        self.lua.execute("q:push({id='a',key='phase',text='old'});q:push({id='b',key='phase',text='other'});q:push({id='a',key='phase',text='fight',priority=true})")
        self.assertEqual(self.lua.eval('q.count'),2)
        self.assertEqual(self.lua.eval('q:pop(0).text'),'fight')
        self.assertEqual(self.lua.eval('q:pop(0).text'),'other')

    def test_discard_removes_head_middle_and_tail_without_breaking_queue(self):
        self.lua.execute("for i=1,3 do q:push({id='a',key=tostring(i),text=tostring(i)})end;q:discard('a','2');q:discard('a','1');q:discard('a','3');q:push({id='b',text='fresh'})")
        self.assertEqual(self.lua.eval('q.count'),1)
        self.assertEqual(self.lua.eval('q:pop(0).text'),'fresh')
        self.assertIsNone(self.lua.eval('q:pop(0)'))

    def test_long_multibyte_message_is_truncated_at_character_boundary(self):
        self.lua.execute(NATIVE_MOCKS)
        self.lua.execute("config=require('config');adapter=require('adapter').new(config,print);adapter:refresh();id=adapter:identify(pc1)")
        self.lua.globals().long_text='x'*1499+'🐉'*5
        self.lua.execute("adapter:message(id,long_text);m=adapter.outbox:pop(0)")
        self.assertEqual(self.lua.eval('m.text'),'x'*1499)

    def test_match_cleanup_removes_stale_warnings_but_keeps_personal_replies(self):
        self.lua.execute(NATIVE_MOCKS)
        self.lua.execute("""config=require('config');adapter=require('adapter').new(config,print)
            adapter:message('p1','fight',{priority=true,key='phase:1'})
            adapter:message('p1','boundary',{priority=true,key='boundary:1'})
            adapter:message('p1','items');adapter:clear_notices('p1',1)""")
        self.assertEqual(self.lua.eval('adapter.outbox.count'),1)
        self.assertEqual(self.lua.eval('adapter.outbox:pop(0).text'),'items')


if __name__ == '__main__':
    unittest.main()
