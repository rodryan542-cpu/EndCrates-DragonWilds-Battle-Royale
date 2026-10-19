from pathlib import Path
import tempfile
import unittest

from support import runtime
from native_support import NATIVE_MOCKS


class CatalogueTests(unittest.TestCase):
    def setUp(self):
        self.lua=runtime();self.lua.execute(NATIVE_MOCKS)
        self.lua.execute("catalogue=require('catalogue').new()")

    def test_catalogue_contains_asset_names_without_loading_assets(self):
        self.assertGreater(self.lua.eval('#catalogue.rows'),1400)
        self.assertIsNone(self.lua.globals().load_count)

    def test_exact_name_resolves_and_ambiguous_search_rejects(self):
        self.assertEqual(self.lua.eval("catalogue:unique('Scimitar_Dragon').name"),'ITEM_Scimitar_Dragon')
        self.lua.execute("ambiguous=pcall(catalogue.unique,catalogue,'dragon')")
        self.assertFalse(self.lua.globals().ambiguous)

    def test_query_cache_is_bounded(self):
        self.lua.execute("for i=1,100 do catalogue:find('search'..i) end")
        self.assertEqual(self.lua.eval('#catalogue.query_order'),64)

    def test_missing_asset_is_rejected(self):
        self.lua.execute("ok=pcall(catalogue.asset,catalogue,catalogue:unique('Scimitar_Dragon'))")
        self.assertFalse(self.lua.globals().ok)
        self.assertEqual(self.lua.globals().load_count,1)

    def test_deprecated_asset_is_not_added(self):
        self.lua.execute("before=#catalogue.rows;catalogue:add({name='Old',path='/Game/Deleted/Old.Old'})")
        self.assertEqual(self.lua.eval('#catalogue.rows'),self.lua.globals().before)


class PersistenceTests(unittest.TestCase):
    def test_geometry_roundtrip_preserves_quoted_names_and_previous_copy(self):
        lua=runtime();lua.execute("P=require('persistence');c={world_id='world',lobby={x=1,y=2,z=3,radius=1000},zones={{id='test',spawns={}}}}")
        with tempfile.TemporaryDirectory(prefix='BR config ') as temporary:
            root=Path(temporary)
            (root/'config.lua').write_text('return {}',encoding='utf-8')
            lua.globals().test_search_path=root.as_posix()+'/?.lua'
            lua.execute("package.path=test_search_path;assert(P.save(c));c.world_id='other';assert(P.save(c));out={};assert(P.load(out))")
            self.assertEqual(lua.eval('out.world_id'),'other')
            self.assertTrue((root/'arena_state.lua.previous').exists())
            self.assertIn('world',(root/'arena_state.lua.previous').read_text(encoding='utf-8'))

    def test_saved_state_cannot_reenable_matches(self):
        lua=runtime();lua.execute("P=require('persistence');c={enabled=true,world_id='world',lobby={x=1,y=2,z=3,radius=1000},zones={}}")
        with tempfile.TemporaryDirectory(prefix='BR config ') as temporary:
            root=Path(temporary);(root/'config.lua').write_text('return {}',encoding='utf-8')
            lua.globals().test_search_path=root.as_posix()+'/?.lua'
            lua.execute("package.path=test_search_path;assert(P.save(c));out={enabled=false};assert(P.load(out))")
            self.assertFalse(lua.eval('out.enabled'))


if __name__=='__main__':
    unittest.main()
