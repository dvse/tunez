defmodule Tunez.HTMLParity do
  @moduledoc false

  require Phoenix.LiveViewTest

  @framework_attribute_prefixes ["phx-", "data-phx-", "data-blueprint-"]
  @viewport_widths [390, 1440]
  @chrome "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

  def render_upstream_screens! do
    project = File.cwd!()
    upstream = Path.expand("../tunez_upstream", project)
    script = Path.join(project, "test/support/upstream_oracle.exs")

    {output, status} =
      System.cmd("mix", ["run", script],
        cd: upstream,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    ExUnit.Assertions.assert(status == 0, "upstream Tunez oracle failed:\n#{output}")

    encoded =
      case Regex.run(~r/ASH_BLUEPRINT_UPSTREAM_ORACLE=([A-Za-z0-9+\/=]+)/, output) do
        [_, encoded] -> encoded
        _other -> raise "upstream Tunez oracle emitted no result:\n#{output}"
      end

    encoded
    |> Base.decode64!()
    |> :erlang.binary_to_term([:safe])
  end

  def render_blueprint(record, actor \\ nil) do
    record
    |> AshBlueprint.Runtime.ResourceInfo.render_tree_for_record(
      actor: actor,
      context: %{current_user: actor}
    )
    |> then(fn {:ok, tree} -> tree end)
    |> AshBlueprint.RenderTarget.Html.render_static()
    |> then(fn {:safe, iodata} -> IO.iodata_to_binary(iodata) end)
  end

  def render_original(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  def render_original(component, assigns) when is_function(component, 1) and is_map(assigns) do
    Phoenix.LiveViewTest.render_component(component, Map.to_list(assigns))
  end

  def assert_same!(original, blueprint) do
    normalized_original = normalize(original)
    normalized_blueprint = normalize(blueprint)

    html_failures =
      if normalized_blueprint == normalized_original do
        []
      else
        [
          """
          normalized HTML differs

          ORIGINAL:
          #{normalized_original}

          BLUEPRINT:
          #{normalized_blueprint}
          """
        ]
      end

    style_failures =
      Enum.flat_map(@viewport_widths, fn width ->
        try do
          assert_computed_styles_same!(original, blueprint, width)
          []
        rescue
          error in [ExUnit.AssertionError] -> [Exception.message(error)]
        end
      end)

    ExUnit.Assertions.assert(html_failures ++ style_failures == [],
      Enum.join(html_failures ++ style_failures, "\n\n")
    )
  end

  def assert_screen_same!(original, blueprint, part) do
    blueprint =
      blueprint
      |> Floki.parse_fragment!()
      |> Floki.find(~s([part="#{part}"]))
      |> case do
        [{_tag, _attrs, children}] -> Floki.raw_html(children)
        nodes -> raise "expected one Blueprint part #{inspect(part)}, got #{length(nodes)}"
      end

    assert_same!(original, blueprint)
  end

  def assert_app_same!(original, blueprint, scenario) do
    original =
      extract_one!(
        original,
        ~s(div[class~="w-full"][class~="max-w-6xl"][class~="m-auto"]),
        scenario
      )

    blueprint = extract_one!(blueprint, ~s([part="app_root"]), scenario)
    assert_same!(original, blueprint)
  end

  def normalize(html) when is_binary(html) do
    html
    |> Floki.parse_fragment!()
    |> Enum.map(&normalize_node/1)
    |> Enum.reject(&is_nil/1)
    |> Floki.raw_html(encode: false)
  end

  def assert_computed_styles_same!(original, blueprint, viewport_width) do
    chrome = System.get_env("CHROME_BIN", @chrome)

    ExUnit.Assertions.assert(
      File.exists?(chrome),
      "computed-style parity requires Chrome at #{chrome}; set CHROME_BIN to override"
    )

    css = File.read!(Path.expand("../../priv/static/assets/app.css", __DIR__))
    token = Ash.UUID.generate()
    directory = Path.join(System.tmp_dir!(), "tunez-style-parity-#{token}")
    File.mkdir_p!(directory)
    page_path = Path.join(directory, "parity.html")
    profile_path = Path.join(directory, "chrome-profile")
    dump_path = Path.join(directory, "dump.html")

    File.write!(page_path, computed_style_page(css, original, blueprint))

    try do
      {dump, status} =
        System.cmd(
          "/bin/sh",
          [
            "-c",
            chrome_dump_script(),
            "tunez-computed-style-harness",
            chrome,
            page_path,
            dump_path,
            profile_path,
            Integer.to_string(viewport_width)
          ],
          stderr_to_stdout: true
        )

      ExUnit.Assertions.assert(status == 0, "Chrome style harness failed:\n#{dump}")

      result =
        dump
        |> Floki.parse_document!()
        |> Floki.find("#computed-style-result")
        |> Floki.text()
        |> Jason.decode!()

      ExUnit.Assertions.assert(
        result["mismatches"] == [],
        """
        computed styles differ across #{result["element_count"]} elements at #{viewport_width}px

        #{Jason.encode!(result["mismatches"], pretty: true)}
        """
      )
    after
      File.rm_rf!(directory)
    end
  end

  defp chrome_dump_script do
    """
    "$1" --headless=new --disable-gpu --no-sandbox --allow-file-access-from-files \
      --window-size="$5,900" \
      --run-all-compositor-stages-before-draw --virtual-time-budget=3000 \
      --user-data-dir="$4" --dump-dom "$2" >"$3" 2>&1 &
    pid=$!
    found=0
    i=0
    while [ "$i" -lt 200 ]; do
      if grep -q '<pre id="computed-style-result">{' "$3" 2>/dev/null; then
        found=1
        break
      fi
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      i=$((i + 1))
      sleep 0.05
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    cat "$3"
    [ "$found" -eq 1 ]
    """
  end

  defp computed_style_page(css, original, blueprint) do
    """
    <!doctype html>
    <html>
      <head><meta charset="utf-8"><style>#{css}</style></head>
      <body>
        <div id="parity-original" style="position: fixed; left: -2000px; top: 0; width: 100%; min-height: 900px">#{original}</div>
        <div id="parity-blueprint" style="position: fixed; left: -4000px; top: 0; width: 100%; min-height: 900px">#{blueprint}</div>
        <script>
          function elements(root) {
            return Array.from(root.querySelectorAll("*")).filter(
              element =>
                !element.matches('input[type="hidden"], br, [part="sort_gap"]') &&
                !(element.tagName === "LABEL" &&
                  (element.textContent.trim() === "" || getComputedStyle(element).display === "none"))
            );
          }

          function styles(element) {
            const computed = element.ownerDocument.defaultView.getComputedStyle(element);
            return Object.fromEntries(
              Array.from(computed).sort().map(name => [name, computed.getPropertyValue(name)])
            );
          }

          function compare(originalElements, blueprintElements) {
            const mismatches = [];
            const count = Math.max(originalElements.length, blueprintElements.length);

            for (let index = 0; index < count; index++) {
              const original = originalElements[index];
              const blueprint = blueprintElements[index];
              const path = `${index}:${original?.tagName?.toLowerCase() || "missing"}`;

              if (!original || !blueprint || original.tagName !== blueprint.tagName) {
                mismatches.push({path, property: "<element>", original: original?.tagName, blueprint: blueprint?.tagName});
                continue;
              }

              const originalStyles = styles(original);
              const blueprintStyles = styles(blueprint);
              const properties = new Set([...Object.keys(originalStyles), ...Object.keys(blueprintStyles)]);

              for (const property of properties) {
                if (originalStyles[property] !== blueprintStyles[property]) {
                  mismatches.push({
                    path,
                    property,
                    original: originalStyles[property],
                    blueprint: blueprintStyles[property],
                    original_element: original.outerHTML.slice(0, 500),
                    blueprint_element: blueprint.outerHTML.slice(0, 500)
                  });
                }
              }
            }

            return {element_count: count, mismatches};
          }

          const result = compare(
            elements(document.getElementById("parity-original")),
            elements(document.getElementById("parity-blueprint"))
          );
          document.body.innerHTML = '<pre id="computed-style-result"></pre>';
          document.getElementById("computed-style-result").textContent = JSON.stringify(result);
        </script>
      </body>
    </html>
    """
  end

  defp normalize_node({tag, attrs, children}) do
    cond do
      tag == "br" -> " "
      tag == "input" and Enum.member?(attrs, {"type", "hidden"}) -> nil
      tag == "label" and implementation_label?(attrs, children) -> nil
      Enum.member?(attrs, {"part", "sort_gap"}) -> nil
      true -> normalize_element({tag, attrs, children})
    end
  end

  defp normalize_node(text) when is_binary(text) do
    case text |> String.replace(~r/\s+/, " ") |> String.trim() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_node(other), do: other

  defp normalize_element({tag, attrs, children}) do
    attrs =
      attrs
      |> Enum.reject(fn {name, value} ->
        name == "class" or framework_attribute?(name) or
          form_implementation_attribute?(tag, name, value)
      end)
      |> Enum.map(&normalize_generated_attribute/1)
      |> Enum.sort()

    children = children |> Enum.map(&normalize_node/1) |> Enum.reject(&is_nil/1)
    {tag, attrs, children}
  end

  defp framework_attribute?("part"), do: true
  defp framework_attribute?("aria-selected"), do: true
  defp framework_attribute?(name) when name in ["data-hidden-label", "data-kind"], do: true

  defp framework_attribute?(name) do
    Enum.any?(@framework_attribute_prefixes, &String.starts_with?(name, &1))
  end

  defp form_implementation_attribute?(tag, name, _value)
       when tag in ["form", "input", "select", "textarea"] and
              name in ["action", "method", "name"],
       do: true

  defp form_implementation_attribute?("input", "type", "text"), do: true
  defp form_implementation_attribute?(_tag, _name, _value), do: false

  defp implementation_label?(attrs, children) do
    Enum.member?(attrs, {"part", "hidden_label"}) or
      Enum.any?(attrs, fn
        {"class", classes} -> "hidden" in String.split(classes)
        _attribute -> false
      end) or Enum.all?(children, &(&1 in [nil, ""]))
  end

  defp normalize_generated_attribute({"id", "dropdown_" <> generated} = attribute) do
    case Ecto.UUID.cast(generated) do
      {:ok, _uuid} -> {"id", "dropdown_generated"}
      :error -> attribute
    end
  end

  defp normalize_generated_attribute(attribute), do: attribute

  defp extract_one!(html, selector, scenario) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> case do
      [node] -> Floki.raw_html([node])
      nodes -> raise "#{scenario}: expected one #{selector}, got #{length(nodes)}"
    end
  end
end
