-- Persistent, presentation-only variation. Values are semantic production ids,
-- not runtime material, mesh, or attachment objects.

---@class CosmeticVariantData
---@field id string
---@field presentation_id string
---@field material_variant_id string
---@field head_variant_id string?
---@field accessory_id string?

---@type table<string, CosmeticVariantData>
return {
    rook_ember = {
        id = "rook_ember",
        presentation_id = "medieval_rook_emberguard",
        material_variant_id = "ember_bronze",
        head_variant_id = "closed_helm",
    },
    rook_steel = {
        id = "rook_steel",
        presentation_id = "medieval_rook_emberguard",
        material_variant_id = "moonlit_steel",
        head_variant_id = "open_helm",
    },
    bramble_moss = {
        id = "bramble_moss",
        presentation_id = "medieval_bramble_quickstep",
        material_variant_id = "moss_green",
        accessory_id = "short_cape",
    },
    bramble_berry = {
        id = "bramble_berry",
        presentation_id = "medieval_bramble_quickstep",
        material_variant_id = "berry_red",
        accessory_id = "belt_pouch",
    },
    nova_cyan = {
        id = "nova_cyan",
        presentation_id = "scifi_nova_quell",
        material_variant_id = "ion_cyan",
        head_variant_id = "visor_clear",
    },
    nova_magenta = {
        id = "nova_magenta",
        presentation_id = "scifi_nova_quell",
        material_variant_id = "nova_magenta",
        head_variant_id = "visor_dark",
    },
    axi_blue = {
        id = "axi_blue",
        presentation_id = "scifi_axi",
        material_variant_id = "signal_blue",
        head_variant_id = "sensor_round",
    },
    axi_orange = {
        id = "axi_orange",
        presentation_id = "scifi_axi",
        material_variant_id = "signal_orange",
        head_variant_id = "sensor_split",
    },
    moxie_sun = {
        id = "moxie_sun",
        presentation_id = "toy_moxie_modular",
        material_variant_id = "sunburst",
        head_variant_id = "heroic",
    },
    moxie_ocean = {
        id = "moxie_ocean",
        presentation_id = "toy_moxie_modular",
        material_variant_id = "ocean",
        head_variant_id = "adventure",
    },
    tock_brass = {
        id = "tock_brass",
        presentation_id = "toy_tock",
        material_variant_id = "brass",
        accessory_id = "square_key",
    },
    tock_cherry = {
        id = "tock_cherry",
        presentation_id = "toy_tock",
        material_variant_id = "cherry",
        accessory_id = "round_key",
    },
}
