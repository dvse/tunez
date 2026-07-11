# Tunez audit-gate exceptions

All workspace Ash and AshBlueprint rules apply. The following is the only approved deviation.

## Artist catalogue relationship

`Tunez.UI.ArtistIndexPage.ArtistsRelationship` may implement the `:artists` and
`:next_artist` Ash relationships as one manual relationship with `:page` and
`:next` modes. It must remain a relationship load, call only the typed
`Tunez.Music.browse_artists/2` domain code interface, and propagate the complete
Ash scope.

Proof: stock relationship filters can correlate destination fields with parent
attributes through `parent/1`, but the relationship DSL cannot bind parent row
attributes to destination read-action arguments or express a parent-dependent
dynamic sort, limit, and offset. `Tunez.Music.Artist.browse` requires the typed
`:query`, `:sort_by`, `:limit`, and `:offset` arguments because the UI page owns
those values; the UI row is ETS-backed while artists are Postgres-backed, so no
single data-layer join can implement the window. Checked
`deps/ash/documentation/topics/resources/relationships.md` (the
`no_attributes? true` and `Manual Relationships` sections),
`deps/ash/lib/ash/resource/relationships/shared_options.ex` (relationship
`read_action`, filter, sort, and manual schemas), and
`deps/ash/lib/ash/actions/read/relationships.ex` (destination query/action
argument handling). The smallest exception is this relationship loader; no UI
action, calculation, bridge, or helper may read the catalogue directly.

Cleanup condition: delete the manual relationship when stock Ash relationships
can bind parent attributes to typed destination action arguments including
dynamic sort/limit/offset across these data layers.
