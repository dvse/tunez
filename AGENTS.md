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

## AppShell avatar seed

`Tunez.UI.AppShell.mount` may use one action-local `change fn` to derive the
lowercase SHA-256 avatar seed from its typed `:email` argument and write the
concrete `:avatar_seed` attribute.

Proof: the hash itself is expressible with stock Ash function fragments, but a
lazy store child is previewed through
`AshBlueprint.Runtime.ResourceComponentRender.build_store_prototype/3`, which
calls only `Ash.Changeset.apply_attributes/1`. Ash keeps `atomic_set` values in
`create_atomics` for the later data-layer create phase; `apply_attributes/1`
does not evaluate them. `set_attribute` accepts a literal, argument template,
or zero-arity function and does not evaluate an Ash expression; defaults cannot
read sibling state; `update_change` installs a skipped `before_action` hook.
Checked `ash_blueprint/lib/ash_blueprint/runtime/resource_component_render.ex`,
Ash `changeset.ex`, `atomic_set.ex`, `set_attribute.ex`, `attribute.ex`,
`update_change.ex`, and the ETS data-layer create evaluator. The callback is the
smallest exception: it is inline in the owning Ash action, reads one typed
argument, writes one modeled attribute, and creates no helper or alternate
state path.

Cleanup condition: replace the callback with `atomic_set` when Ash exposes a
public changeset-preview API that evaluates create atomics without persisting,
and AshBlueprint uses that API for lazy store prototypes.


## Page-life clock

`Tunez.UI.PageLife` is the session's navigation clock; every routed page's
`:mount` declares `change Tunez.UI.Changes.BeginPageLife` (a reused change is
justified: nine resources declare the identical lifecycle fact through the
`Tunez.UI.begin_page_life/2` domain interface with full scope). Flash rows are
stamped with the life they were put in; visibility is the pure comparison in
`Tunez.UI.Flash.visible?`. Failure flashes are NOT rows: they are projections
of the dispatch's fieldless errors (`errors()` in `Tunez.UI.FlashStack`),
which gives them per-dispatch transience with zero lifecycle state.

## Album track materialization

`Tunez.UI.AlbumFormPage.mount` performs one domain-interface read
(`Tunez.Music.get_manageable_album_by_id/2`) to materialize track draft rows.
This is the collection-copy the nested UI model requires: dispatch-receiving
embedded rows must be stored instances, so a `||` overlay cannot express an
editable collection. The read is non-authoritative — on failure the seed is
skipped and `manage_relationship`'s policy-checked lookup owns the outcome.
