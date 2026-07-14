defmodule Tunez.HTMLParity do
  @moduledoc false

  require Phoenix.LiveViewTest

  @framework_attribute_prefixes ["phx-", "data-phx-", "data-blueprint-"]
  @viewport_widths [390, 640, 768, 1024, 1440]
  # Computed-style parity needs a headless Chromium-family browser. Honour
  # CHROME_BIN first, then probe the usual per-OS locations (Linux CI installs
  # `chromium`/`google-chrome`; macOS dev boxes carry Google Chrome in
  # /Applications). The first existing path wins.
  @chrome_candidates [
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  ]
  @batch_key {__MODULE__, :computed_style_batch}

  def begin_batch! do
    {:ok, batch} = Agent.start(fn -> [] end)
    Process.put(@batch_key, batch)
    batch
  end

  def assert_batch!(batch) when is_pid(batch) do
    cases = Agent.get(batch, &Enum.reverse/1)

    try do
      assert_computed_styles_same!(cases, @viewport_widths)
    after
      Agent.stop(batch)
    end
  end

  def render_upstream_screens! do
    project = File.cwd!()
    upstream = Path.expand("../tunez_upstream", project)
    script = Path.join(project, "test/support/upstream_oracle.exs")

    {output, status} =
      System.cmd("mix", ["run", script],
        cd: upstream,
        env: [{"MIX_ENV", "test"}, {"ERL_FLAGS", "+S 2:2"}],
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

  def render_blueprint_document do
    # Mirror what the app actually serves: the app-level document wrapper adds
    # the html/body chrome over the framework RootLayout skeleton.
    {:safe, iodata} = TunezWeb.Router.app_document(%{inner_content: ""})
    IO.iodata_to_binary(iodata)
  end

  def assert_same!(original, blueprint, label \\ "comparison") do
    normalized_original = normalize(original)
    normalized_blueprint = normalize(blueprint)

    ExUnit.Assertions.assert(
      normalized_blueprint == normalized_original,
      """
      #{label}: normalized HTML differs

      ORIGINAL:
      #{normalized_original}

      BLUEPRINT:
      #{normalized_blueprint}
      """
    )

    case Process.get(@batch_key) do
      batch when is_pid(batch) ->
        Agent.update(batch, &[{:fragment, label, original, blueprint} | &1])

      _no_batch ->
        assert_computed_styles_same!([{:fragment, label, original, blueprint}], @viewport_widths)
    end
  end

  def assert_document_same!(original, blueprint, label \\ "document shell") do
    original_document = Floki.parse_document!(original)
    blueprint_document = Floki.parse_document!(blueprint)

    for selector <- ["title", "html", "body"] do
      original_node = document_node!(original_document, selector, label)
      blueprint_node = document_node!(blueprint_document, selector, label)

      ExUnit.Assertions.assert(
        normalize_document_node(blueprint_node, selector) ==
          normalize_document_node(original_node, selector),
        "#{label}: #{selector} differs"
      )
    end

    case Process.get(@batch_key) do
      batch when is_pid(batch) ->
        Agent.update(batch, &[{:document, label, original, blueprint} | &1])

      _no_batch ->
        assert_computed_styles_same!([{:document, label, original, blueprint}], @viewport_widths)
    end
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

    assert_same!(original, blueprint, to_string(part))
  end

  def assert_app_same!(original, blueprint, scenario) do
    original =
      extract_one!(
        original,
        ~s(div[class~="w-full"][class~="max-w-6xl"][class~="m-auto"]),
        scenario
      )

    blueprint = extract_one!(blueprint, ~s([part="app_root"]), scenario)
    assert_same!(original, blueprint, scenario)
  end

  def normalize(html) when is_binary(html) do
    html
    |> Floki.parse_fragment!()
    |> Enum.map(&normalize_node/1)
    |> Enum.reject(&is_nil/1)
    |> Floki.raw_html(encode: false)
  end

  def assert_computed_styles_same!(original, blueprint, viewport_width) do
    assert_computed_styles_same!(
      [{:fragment, "comparison", original, blueprint}],
      [viewport_width]
    )
  end

  defp assert_computed_styles_same!([], _viewport_widths), do: :ok

  defp assert_computed_styles_same!(cases, viewport_widths) do
    chrome =
      case System.get_env("CHROME_BIN") do
        path when is_binary(path) -> path
        nil -> Enum.find(@chrome_candidates, hd(@chrome_candidates), &File.exists?/1)
      end

    ExUnit.Assertions.assert(
      File.exists?(chrome),
      "computed-style parity requires Chrome; set CHROME_BIN or install one of #{inspect(@chrome_candidates)}"
    )

    blueprint_css = File.read!(Path.expand("../../priv/static/assets/app.css", __DIR__))

    upstream = Path.expand("../../../tunez_upstream", __DIR__)
    original_css_path = Path.join(upstream, "priv/static/assets/app.css")

    unless File.exists?(original_css_path) do
      {output, status} =
        System.cmd("mix", ["assets.build"],
          cd: upstream,
          env: [{"MIX_ENV", "test"}, {"ERL_FLAGS", "+S 2:2"}],
          stderr_to_stdout: true
        )

      ExUnit.Assertions.assert(status == 0, "upstream stylesheet build failed:\n#{output}")
    end

    original_css = File.read!(original_css_path)
    token = Ash.UUID.generate()
    directory = Path.join(System.tmp_dir!(), "tunez-style-parity-#{token}")
    File.mkdir_p!(directory)
    page_path = Path.join(directory, "parity.html")
    profile_path = Path.join(directory, "chrome-profile")
    dump_path = Path.join(directory, "dump.html")

    File.write!(
      page_path,
      computed_style_page(original_css, blueprint_css, cases, viewport_widths)
    )

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
            profile_path
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
        computed styles differ across #{result["element_count"]} compared elements

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
      --window-size="1600,1000" \
      --run-all-compositor-stages-before-draw --virtual-time-budget=20000 \
      --user-data-dir="$4" --dump-dom "$2" >"$3" 2>&1 &
    pid=$!
    found=0
    i=0
    while [ "$i" -lt 600 ]; do
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

  defp computed_style_page(original_css, blueprint_css, cases, viewport_widths) do
    payload =
      for {kind, label, original, blueprint} <- cases,
          width <- viewport_widths do
        %{
          kind: kind,
          label: label,
          width: width,
          original: original,
          blueprint: blueprint
        }
      end

    original_css = Base.encode64(original_css)
    blueprint_css = Base.encode64(blueprint_css)
    payload = payload |> Jason.encode!() |> Base.encode64()

    """
    <!doctype html>
    <html>
      <head><meta charset="utf-8"></head>
      <body>
        <script>
          function decode64(value) {
            const binary = atob(value);
            return new TextDecoder().decode(Uint8Array.from(binary, character => character.charCodeAt(0)));
          }

          function comparable(element) {
            return (
              !element.matches('input[type="hidden"]') &&
              !(element.tagName === "LABEL" &&
                (element.textContent.trim() === "" || getComputedStyle(element).display === "none"))
            );
          }

          function elements(document, kind) {
            if (kind === "document") {
              return [document.documentElement, document.body];
            }

            const root = document.getElementById("parity-root");
            return Array.from(root.children).flatMap(
              element => [element, ...element.querySelectorAll("*")]
            ).filter(
              element =>
                comparable(element)
            );
          }

          function styles(element) {
            const computed = element.ownerDocument.defaultView.getComputedStyle(element);

            function canonicalValue(name, value) {
              if (name !== "text-align") return value;

              if (computed.direction === "rtl") {
                if (value === "start") return "right";
                if (value === "end") return "left";
              } else {
                if (value === "start") return "left";
                if (value === "end") return "right";
              }

              return value;
            }

            return Object.fromEntries(
              Array.from(computed).sort().map(
                name => [name, canonicalValue(name, computed.getPropertyValue(name))]
              )
            );
          }

          function compare(testCase, originalElements, blueprintElements) {
            const mismatches = [];
            const count = Math.max(originalElements.length, blueprintElements.length);

            for (let index = 0; index < count; index++) {
              const original = originalElements[index];
              const blueprint = blueprintElements[index];
              const path = `${testCase.label}@${testCase.width}px:${index}:${original?.tagName?.toLowerCase() || "missing"}`;

              if (!original || !blueprint) {
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

          function documentSource(html, css, kind) {
            if (kind === "document") {
              return html.replace(/<head([^>]*)>/i, `<head$1><style>${css}</style>`);
            }

            return `<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body><div id="parity-root" style="width:100%;min-height:900px">${html}</div></body></html>`;
          }

          async function mountFrame(html, css, testCase) {
            const frame = document.createElement("iframe");
            frame.style.width = `${testCase.width}px`;
            frame.style.height = "900px";
            frame.srcdoc = documentSource(html, css, testCase.kind);
            document.body.appendChild(frame);
            await new Promise(resolve => frame.addEventListener("load", resolve, {once: true}));
            return frame;
          }

          function synchronizeAnimations(document) {
            for (const animation of document.getAnimations({subtree: true})) {
              animation.pause();
              animation.currentTime = 0;
            }

            document.documentElement.getBoundingClientRect();
          }

          function removeObsoleteOracleArtifacts(document) {
            const saveError = document.getElementById("flash-error");
            const message = saveError?.textContent.trim().replace(/\s+/g, " ");

            if (message === "Could not save album data" || message === "Could not save artist data") {
              saveError.remove();
            }
          }

          async function run() {
            const originalCss = decode64("#{original_css}");
            const blueprintCss = decode64("#{blueprint_css}");
            const testCases = JSON.parse(decode64("#{payload}"));
            const result = {element_count: 0, mismatches: []};

            for (const testCase of testCases) {
              const originalFrame = await mountFrame(testCase.original, originalCss, testCase);
              const blueprintFrame = await mountFrame(testCase.blueprint, blueprintCss, testCase);
              removeObsoleteOracleArtifacts(originalFrame.contentDocument);
              removeObsoleteOracleArtifacts(blueprintFrame.contentDocument);
              synchronizeAnimations(originalFrame.contentDocument);
              synchronizeAnimations(blueprintFrame.contentDocument);
              const comparison = compare(
                testCase,
                elements(originalFrame.contentDocument, testCase.kind),
                elements(blueprintFrame.contentDocument, testCase.kind)
              );

              result.element_count += comparison.element_count;
              result.mismatches.push(...comparison.mismatches);
              originalFrame.remove();
              blueprintFrame.remove();
            }

            document.body.innerHTML = '<pre id="computed-style-result"></pre>';
            document.getElementById("computed-style-result").textContent = JSON.stringify(result);
          }

          run();
        </script>
      </body>
    </html>
    """
  end

  defp normalize_node({tag, attrs, children}) do
    cond do
      tag == "input" and Enum.member?(attrs, {"type", "hidden"}) ->
        nil

      obsolete_upstream_save_flash?(tag, attrs, children) ->
        nil

      tag == "label" and phoenix_form_label_noise?(attrs, children) ->
        nil

      pagination_control?(attrs) ->
        normalize_element({"button", pagination_attrs(attrs), children})

      delete_control?(tag, attrs, children) ->
        normalize_element({"button", delete_control_attrs(attrs), children})

      true ->
        normalize_element({tag, attrs, children})
    end
  end

  defp normalize_node(text) when is_binary(text) do
    case text |> String.replace(~r/\s+/, " ") |> String.trim() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_node(other), do: other

  # The Ash UI keeps the original action/changeset errors as its sole error
  # model. The upstream Phoenix forms add this generic second error alongside
  # the useful field error; ignore only that exact obsolete oracle artifact.
  defp obsolete_upstream_save_flash?("div", attrs, children) do
    Enum.member?(attrs, {"id", "flash-error"}) and
      children
      |> Floki.text()
      |> String.trim()
      |> then(&(&1 in ["Could not save album data", "Could not save artist data"]))
  end

  defp obsolete_upstream_save_flash?(_tag, _attrs, _children), do: false

  # URL-link paging (upstream) and action paging (blueprint) are the same
  # control: both project offset/limit into the URL. Canonicalize to a
  # button and drop the transport-specific href/type.
  defp pagination_control?(attrs) do
    Enum.any?(attrs, fn {k, v} ->
      k == "data-role" and v in ["previous-page", "next-page"]
    end)
  end

  # The row delete control is an upstream anchor and a Blueprint button.
  # Both retain the same hidden label and icon children; only the transport
  # element and its href/type attributes need canonicalizing.
  defp delete_control?("button", attrs, _children),
    do: Enum.member?(attrs, {"part", "track_delete_link"})

  defp delete_control?("a", attrs, children) do
    Enum.member?(attrs, {"href", "#"}) and
      Enum.any?(children, fn
        {"span", _, kids} ->
          Enum.any?(kids, &(is_binary(&1) and String.trim(&1) == "Delete"))

        _other ->
          false
      end)
  end

  defp delete_control?(_tag, _attrs, _children), do: false

  defp delete_control_attrs(attrs) do
    Enum.reject(attrs, fn {name, _value} -> name in ["href", "type"] end)
  end

  defp pagination_attrs(attrs) do
    Enum.reject(attrs, fn {k, _v} -> k in ["href", "type"] end)
  end

  defp normalize_element({tag, attrs, children}) do
    notifications_toggle? = Enum.member?(attrs, {"part", "notifications_toggle"})

    state_projection? =
      Enum.any?(attrs, fn
        {"part", part} when part in ["user_menu", "notifications_panel", "page_header_menu"] ->
          true

        _attribute ->
          false
      end)

    attrs =
      attrs
      |> Enum.reject(fn {name, value} ->
        name == "class" or framework_attribute?(name) or
          datastar_generated_attribute?(name, value) or
          accessibility_implementation_attribute?(tag, attrs, name) or
          form_implementation_attribute?(tag, name, value) or
          (notifications_toggle? and name == "tabindex") or
          (state_projection? and name in ["aria-expanded", "open"])
      end)
      |> Enum.map(&normalize_generated_attribute/1)
      |> Enum.sort()

    children = children |> Enum.map(&normalize_node/1) |> Enum.reject(&is_nil/1)
    {tag, attrs, children}
  end

  defp accessibility_implementation_attribute?(_tag, attrs, "role") do
    Enum.member?(attrs, {"part", "field_error"})
  end

  # Blueprint distributes field errors ARIA-first (aria-invalid on the
  # bound control); upstream renders only the error text element.
  defp accessibility_implementation_attribute?(tag, _attrs, "aria-invalid")
       when tag in ["input", "select", "textarea"],
       do: true

  # Blueprint projects declared states ARIA-first (aria-selected on the
  # follow toggle); upstream signals the same state via classes only.
  defp accessibility_implementation_attribute?(_tag, _attrs, "aria-selected"), do: true

  defp accessibility_implementation_attribute?("button", attrs, "aria-label") do
    Enum.member?(attrs, {"part", "track_delete_link"})
  end

  defp accessibility_implementation_attribute?("input", attrs, "aria-label") do
    Enum.any?(attrs, fn
      {"id", "album_form_tracks_" <> _rest} -> true
      _attribute -> false
    end)
  end

  defp accessibility_implementation_attribute?(_tag, _attrs, _name), do: false

  defp framework_attribute?("part"), do: true
  defp framework_attribute?(name) when name in ["data-hidden-label", "data-kind"], do: true

  defp framework_attribute?(name) do
    Enum.any?(@framework_attribute_prefixes, &String.starts_with?(name, &1))
  end

  defp datastar_generated_attribute?(name, _value)
       when name in ["data-bind", "data-init"],
       do: true

  defp datastar_generated_attribute?("data-on-" <> _event, _value), do: true
  defp datastar_generated_attribute?("data-on:" <> _event, _value), do: true

  defp datastar_generated_attribute?("id", "bp-" <> generated),
    do: Regex.match?(~r/^[A-Za-z0-9_-]{16}$/, generated)

  defp datastar_generated_attribute?(_name, _value), do: false

  defp form_implementation_attribute?(tag, name, _value)
       when tag in ["form", "input", "select", "textarea"] and
              name in ["action", "method", "name"],
       do: true

  defp form_implementation_attribute?("input", "type", "text"), do: true
  defp form_implementation_attribute?("input", "value", ""), do: true
  defp form_implementation_attribute?(_tag, _name, _value), do: false

  defp phoenix_form_label_noise?(attrs, children) do
    Enum.member?(attrs, {"part", "hidden_label"}) or
      Enum.any?(attrs, fn
        {"class", classes} -> "hidden" in String.split(classes)
        _attribute -> false
      end) or
      Enum.all?(children, fn child ->
        is_nil(child) or (is_binary(child) and String.trim(child) == "")
      end)
  end

  defp normalize_generated_attribute({"id", "dropdown_" <> generated} = attribute) do
    case Ecto.UUID.cast(generated) do
      {:ok, _uuid} -> {"id", "dropdown_generated"}
      :error -> attribute
    end
  end

  # Datastar is forwarded under /ds; routed anchors retain that prefix as
  # their native/no-JS fallback. It is transport location, not UI structure.
  defp normalize_generated_attribute({"href", "/ds"}), do: {"href", "/"}

  defp normalize_generated_attribute({"href", "/ds/" <> path}),
    do: {"href", "/" <> path}

  defp normalize_generated_attribute({name, value})
       when name in [
              "allowfullscreen",
              "async",
              "autofocus",
              "autoplay",
              "checked",
              "controls",
              "default",
              "defer",
              "disabled",
              "formnovalidate",
              "hidden",
              "inert",
              "ismap",
              "itemscope",
              "loop",
              "multiple",
              "muted",
              "nomodule",
              "novalidate",
              "open",
              "playsinline",
              "readonly",
              "required",
              "reversed",
              "selected"
            ] and value != "false",
       do: {name, ""}

  defp normalize_generated_attribute(attribute), do: attribute

  defp document_node!(document, selector, label) do
    case Floki.find(document, selector) do
      [node] -> node
      nodes -> raise "#{label}: expected one #{selector}, got #{length(nodes)}"
    end
  end

  defp normalize_document_node({"title", _attrs, children}, "title") do
    children
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_document_node({tag, attrs, _children}, tag) when tag in ["html", "body"] do
    attrs
    |> Enum.reject(fn {name, value} ->
      name == "style" or datastar_generated_attribute?(name, value)
    end)
    |> Enum.sort()
  end

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
