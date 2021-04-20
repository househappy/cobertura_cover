defmodule CoberturaCover do
  @cobertura_xml_prefix [
    ~s(<?xml version="1.0" encoding="utf-8"?>\n),
    ~s(<!DOCTYPE coverage SYSTEM "http://cobertura.sourceforge.net/xml/coverage-04.dtd">\n)
  ]

  def start(compile_path, opts) do
    log("Recording test coverage...")

    with _ <- :cover_mod.start(),
         compile_path <- to_charlist(compile_path),
         results when is_list(results) <- :cover_mod.compile_beam_directory(compile_path),
         html_output <- opts[:html_output]
    do
      fn ->
        generate_cobertura()

        if html_output, do: generate_html(html_output)
      end
    else
      _ ->
        Mix.raise("[#{inspect __MODULE__}] Failed to cover compile directory: #{compile_path}")
    end
  end

  def generate_html(output) do
    log("Generating cover HTML output...")

    File.mkdir_p!(output)
    Enum.each(:cover_mod.modules(), fn mod ->
      {:ok, _} = :cover_mod.analyse_to_file(mod, '#{output}/#{mod}.html', [:html])
    end)
  end

  def generate_cobertura do
    log("Generating Cobertura XML report...")

    File.mkdir_p!("cover")
    File.write("cover/coverage.xml", generate_report())
  end

  defp generate_report do
    :xmerl.export_simple(report_root(), :xmerl_xml, prolog: @cobertura_xml_prefix)
  end

  defp report_root do
    [{
      :coverage,
      [
        timestamp: timestamp(),
        'line-rate': 0,
        'lines-covered': 0,
        'lines-valid': 0,
        'branch-rate': 0,
        'branches-covered': 0,
        'branches-valid': 0,
        complexity: 0,
        version: "1.9",
      ],
      [
        sources: [],
        packages: packages()
      ]
    }]
  end

  defp packages do
    [{:package, [name: "", 'line-rate': 0, 'branch-rate': 0, complexity: 1], [
      classes: Enum.map(:cover_mod.modules, fn mod ->
        #
        # Example:
        #
        # <class branch-rate="0.634920634921" complexity="0.0"
        #  filename="PSPDFKit/PSPDFConfiguration.m" line-rate="0.976377952756"
        #  name="PSPDFConfiguration_m">
        #

        {:class,
          [
            name: inspect(mod),
            filename: Path.relative_to_cwd(mod.module_info(:compile)[:source]),
            'line-rate': 0, 'branch-rate': 0, complexity: 1,
          ],
          [methods: methods(mod), lines: lines(mod)]
        }
      end)
    ]}]
  end

  defp methods(mod) do
    {:ok, functions} = :cover_mod.analyse(mod, :calls, :function)

    functions
    |> Stream.map(&elem(&1, 0))
    |> Stream.map(fn {_m, f, _a} ->
      #
      # Example:
      #
      # <method name="main" signature="([Ljava/lang/String;)V" line-rate="1.0" branch-rate="1.0">
      #
      {:method, [name: to_string(f), signature: "", 'line-rate': 0, 'branch-rate': 0], []}
    end)
    |> Enum.to_list()
  end

  defp lines(mod) do
    {:ok, lines} = :cover_mod.analyse(mod, :calls, :line)

    lines
    |> Stream.filter(fn {{_m, line}, _hits} -> line != 0 end)
    |> Enum.map(fn {{_m, line}, hits} ->
      #
      # Example:
      #
      # <line branch="false" hits="21" number="76"/>
      {:line, [branch: false, hits: hits, number: line], []}
    end)
  end

  defp log(message) do
    Mix.shell.info("\n[#{inspect __MODULE__}] #{message}")
  end

  defp timestamp do
    {mega, seconds, micro} = :os.timestamp()

    mega * 1000000000 + seconds * 1000 + div(micro, 1000)
  end
end
