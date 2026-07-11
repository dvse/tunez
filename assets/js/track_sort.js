import Sortable from "../vendor/Sortable.min"

function metadata(element, attribute) {
  try {
    const value = JSON.parse(element.getAttribute(attribute) || "[]")
    return Array.isArray(value) ? value : []
  } catch (_error) {
    return []
  }
}

export default {
  hooks: {
    AshBlueprintClient: {
      mounted() {
        const runtime = metadata(this.el, "data-blueprint-client-runtimes")
          .find(entry => entry.runtime === "track_sort")
        const action = metadata(this.el, "data-blueprint-client-actions")
          .find(entry => entry.using === "reorder_list")

        if (!runtime || !action) return

        this.trackSort = new Sortable(this.el, {
          handle: '[part="track_editor_handle"]',
          draggable: "tr",
          ghostClass: "bg-gray-100",
          onSort: event => {
            this.dispatchBlueprintClientAction(action, {
              order: this.trackSort.toArray(event.to)
            })
          }
        })
      },

      destroyed() {
        this.trackSort?.destroy()
      }
    }
  }
}
