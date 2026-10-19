return {
    enabled = false, -- Set through !br enable after recording a lobby and arena spawns.
    pvp_world_confirmed = false, -- Enable PvP in the arena world's game settings first.
    players_per_match = 20,
    max_active_matches = 4,
    max_loading_matches = 1,
    spawn_budget_per_tick = 4,
    countdown_seconds = 10,
    loading_timeout = 90,
    arrival_tolerance = 500,
    minimum_spawn_spacing = 300,
    zone_gap = 5000,
    boundary_grace_seconds = 10,
    match_timeout = 0, -- Zero: continue until one player remains.
    knockout_health = 1,
    return_timeout = 180,
    return_retry_seconds = 10,
    idle_peer_retention = 600,
    tick_ms = 250,
    combat_sample_seconds = 1,
    roster_refresh_seconds = 2,
    command_budget_per_tick = 16,
    command_inbox_limit = 256,
    message_budget_per_tick = 8,
    max_pending_messages = 4096,
    item_page_size = 10,
    max_give_count = 9999,
    admin_owner_ids = {}, -- Real server-authenticated OwnerGuid.GuidData values.
    lobby = nil, -- {x=..., y=..., z=..., radius=1500}
    zones = {}, -- {id='...', center={x=...,y=...,z=...}, radius=..., spawns={...}}
}
