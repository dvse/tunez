# Tunez audit-gate exceptions

All workspace Ash and AshBlueprint rules apply. The approved deviations are
recorded below.

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

## AshAuthentication confirmation token payload

`Tunez.Accounts.Token.extra_data` and the extension-generated
`:store_confirmation_changes` action may retain the locked AshAuthentication
`Ash.Type.Map` contract. This is the sole accepted generic token payload. The
four source-declared standard actions must not accept it: `:revoke_token`,
`:revoke_jti`, and `:revoke_all_stored_for_subject` have `accept []`, while
`:store_token` accepts only `:purpose`.

Proof: AshAuthentication 4.14.1 creates `extra_data` as `:map` and rejects any
attribute type other than `Ash.Type.Map`
(`deps/ash_authentication/lib/ash_authentication/token_resource/transformer.ex:73-78,675-682`).
It generates `:store_confirmation_changes` with
`accept [:extra_data, :purpose]` (`transformer.ex:348-369`). Tunez's active
confirmation strategy monitors only `:email`; the locked producer stores the
monitored value as a string in `extra_data`, and the locked consumer reads it
by the strategy's stringified field name
(`deps/ash_authentication/lib/ash_authentication/add_ons/confirmation/actions.ex:67-150`).
Token storage and revocation callers do not supply or consume `extra_data`, so
their generator-copied accepts are removed.

Ash's fixed `fields:` map constraint is not compatible with this locked
contract: declared fields are atom-named and casting/loading rebuilds the map
with those atom keys, while AshAuthentication reads persisted confirmation
keys as strings (`deps/ash/lib/ash/type/map.ex:17-75,360-385,508-515`). With no
`fields:` constraint the type validates only the root map and passes nested
values through (`map.ex:276-292,336-401`). The exception is therefore limited
to the policy-bypassed, server-side AshAuthentication interaction and its
dependency-owned producer/consumer; Tunez code must not parse it or expose
another action that accepts it.

Cleanup condition: delete this exception if Tunez removes confirmation-token
state. Otherwise replace it when AshAuthentication accepts a semantic custom
type or exposes a typed confirmation-payload contract with canonical key
semantics. Re-audit before adding another confirmation monitor field or an
OAuth/OIDC strategy.


## Page-life clock

`Tunez.UI.PageLife` is the session's navigation clock. `Tunez.UI.Blueprint`
declares the compile-verified
`{Tunez.UI.PageLifeDomain, :begin_page_life}` contract once and AshBlueprint
supplies it only to routed mounts. The small domain owns only that interface so
the substrate can compile before the routed resources that `Tunez.UI` itself
registers. Flash rows are stamped with the life they were put in; visibility is
the pure comparison in `Tunez.UI.Flash.visible?`. Failure flashes are NOT rows:
they are projections of the dispatch's fieldless errors (`errors()` in
`Tunez.UI.FlashStack`), which gives them per-dispatch transience with zero
lifecycle state.

## Album track materialization

`Tunez.UI.AlbumFormPage.mount` performs one domain-interface read
(`Tunez.Music.get_manageable_album_by_id/2`) to materialize track draft rows.
This is the collection-copy the nested UI model requires: dispatch-receiving
embedded rows must be stored instances, so a `||` overlay cannot express an
editable collection. The read is non-authoritative — on failure the seed is
skipped and `manage_relationship`'s policy-checked lookup owns the outcome.
