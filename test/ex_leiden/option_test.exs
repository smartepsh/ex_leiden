defmodule ExLeiden.OptionTest do
  use ExUnit.Case, async: true
  alias ExLeiden.Option
  doctest ExLeiden.Option

  describe "validate_opts/1" do
    test "returns default options when given empty map" do
      assert {:ok, options} = Option.validate_opts(%{})
      assert options[:resolution] == 1
      assert options[:quality_function] == :modularity
      assert options[:max_level] == 5
      assert options[:format] == :communities_and_bridges
      assert options[:theta] == 0.01
    end

    test "returns default options when given empty list" do
      assert {:ok, options} = Option.validate_opts([])
      assert options[:resolution] == 1
      assert options[:quality_function] == :modularity
      assert options[:max_level] == 5
      assert options[:format] == :communities_and_bridges
      assert options[:theta] == 0.01
    end

    test "accepts valid resolution" do
      assert {:ok, options} = Option.validate_opts(%{resolution: 2.5})
      assert options[:resolution] == 2.5
      assert {:ok, options} = Option.validate_opts(%{resolution: 0.1})
      assert options[:resolution] == 0.1
      assert {:ok, options} = Option.validate_opts(%{resolution: 10})
      assert options[:resolution] == 10
      assert {:ok, options} = Option.validate_opts(%{resolution: 1})
      assert options[:resolution] == 1
      assert {:ok, options} = Option.validate_opts(%{resolution: 3.14})
      assert options[:resolution] == 3.14
    end

    test "rejects invalid resolution" do
      assert {:error, %{resolution: "must be a positive number"}} =
               Option.validate_opts(%{resolution: 0.0})

      assert {:error, %{resolution: "must be a positive number"}} =
               Option.validate_opts(%{resolution: -1.0})

      assert {:error, %{resolution: "must be a positive number"}} =
               Option.validate_opts(%{resolution: "invalid"})
    end

    test "accepts valid quality_function" do
      assert {:ok, options} = Option.validate_opts(%{quality_function: :modularity})
      assert options[:quality_function] == :modularity

      assert {:ok, options} = Option.validate_opts(%{quality_function: :cpm})
      assert options[:quality_function] == :cpm
    end

    test "rejects invalid quality_function" do
      assert {:error, %{quality_function: "must be :modularity or :cpm"}} =
               Option.validate_opts(%{quality_function: :invalid})

      assert {:error, %{quality_function: "must be :modularity or :cpm"}} =
               Option.validate_opts(%{quality_function: "modularity"})
    end

    test "accepts valid max_level" do
      assert {:ok, options} = Option.validate_opts(%{max_level: 10})
      assert options[:max_level] == 10
      assert {:ok, options} = Option.validate_opts(%{max_level: 1})
      assert options[:max_level] == 1
    end

    test "rejects invalid max_level" do
      assert {:error, %{max_level: "must be a positive integer"}} =
               Option.validate_opts(%{max_level: 0})

      assert {:error, %{max_level: "must be a positive integer"}} =
               Option.validate_opts(%{max_level: -5})

      assert {:error, %{max_level: "must be a positive integer"}} =
               Option.validate_opts(%{max_level: 1.5})

      assert {:error, %{max_level: "must be a positive integer"}} =
               Option.validate_opts(%{max_level: "invalid"})
    end

    test "handles multiple validation errors" do
      invalid_options = %{
        resolution: -1.0,
        quality_function: :invalid,
        max_level: 0
      }

      assert {:error, errors} = Option.validate_opts(invalid_options)

      assert errors.resolution == "must be a positive number"
      assert errors.quality_function == "must be :modularity or :cpm"
      assert errors.max_level == "must be a positive integer"
    end

    test "applies valid options correctly" do
      options = %{
        resolution: 2.5,
        quality_function: :cpm,
        max_level: 10
      }

      assert {:ok, result} = Option.validate_opts(options)
      assert result[:resolution] == 2.5
      assert result[:quality_function] == :cpm
      assert result[:max_level] == 10
    end

    test "converts keyword list to map" do
      options = [
        resolution: 2.0,
        quality_function: :cpm,
        max_level: 8
      ]

      assert {:ok, result} = Option.validate_opts(options)
      assert result[:resolution] == 2.0
      assert result[:quality_function] == :cpm
      assert result[:max_level] == 8
      assert result[:theta] == 0.01
    end

    test "accepts valid theta values" do
      assert {:ok, options} = Option.validate_opts(%{theta: 0.01})
      assert options[:theta] == 0.01

      assert {:ok, options} = Option.validate_opts(%{theta: 0.1})
      assert options[:theta] == 0.1

      assert {:ok, options} = Option.validate_opts(%{theta: 1.0})
      assert options[:theta] == 1.0

      assert {:ok, options} = Option.validate_opts(%{theta: 0.005})
      assert options[:theta] == 0.005
    end

    test "rejects invalid theta values" do
      assert {:error, %{theta: "must be a positive number"}} =
               Option.validate_opts(%{theta: 0.0})

      assert {:error, %{theta: "must be a positive number"}} =
               Option.validate_opts(%{theta: -0.01})

      assert {:error, %{theta: "must be a positive number"}} =
               Option.validate_opts(%{theta: "invalid"})

      assert {:ok, options} = Option.validate_opts(%{theta: nil})
      assert options[:theta] == 0.01
    end

    test "handles multiple validation errors including theta" do
      invalid_options = %{
        resolution: -1.0,
        quality_function: :invalid,
        max_level: 0,
        theta: -0.1
      }

      assert {:error, errors} = Option.validate_opts(invalid_options)

      assert errors.resolution == "must be a positive number"
      assert errors.quality_function == "must be :modularity or :cpm"
      assert errors.max_level == "must be a positive integer"
      assert errors.theta == "must be a positive number"
    end

    test "applies valid options including theta correctly" do
      options = %{
        resolution: 2.5,
        quality_function: :cpm,
        max_level: 10,
        theta: 0.05
      }

      assert {:ok, result} = Option.validate_opts(options)
      assert result[:resolution] == 2.5
      assert result[:quality_function] == :cpm
      assert result[:max_level] == 10
      assert result[:theta] == 0.05
    end
  end
end
