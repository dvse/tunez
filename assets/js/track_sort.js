import Sortable from "../vendor/Sortable.min"

export default {
  hooks: {
    AshBlueprintClient: {
      mounted() {
        if (!this.el.hasAttribute("data-blueprint-binding-reorder")) return

        this.trackSort = new Sortable(this.el, {
          handle: '[part="track_editor_handle"]',
          draggable: "tr",
          ghostClass: "bg-gray-100",
          onSort: event => {
            this.dispatchBlueprintComponentEvent(
              this.el,
              {order: this.trackSort.toArray(event.to)},
              "reorder"
            )
          }
        })
      },

      destroyed() {
        this.trackSort?.destroy()
      }
    }
  }
}
