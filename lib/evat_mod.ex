defmodule EvatMod do
  @moduledoc """
  Documentation for `EvatMod`.
  """
  @default_date Date.from_iso8601!("2016-10-01")
  @default_time Time.from_iso8601!("08:00:00")

  @doc """
  Check api server status is up.

  ## Examples

      iex> EvatMod.health_check()
      %{"status" => "UP"}

  """
  def health_check, do: req_base() |> Req.get!(url: "health") |> Map.get(:body)

  @doc """
  Validate TIN No.

  ## Examples

      iex> EvatMod.tin_validator("C0034186913")
      %{
        "data" => %{
          "address" => "ACRA,  NEAR Dadeban Rd., HOUSE NUMBER 17",
          "name" => "SPRING DATA WORKS. LIMITED",
          "sector" => "Other business support service activities n.e.c.",
          "tin" => "C0034186913",
          "type" => "C"
        },
        "status" => "SUCCESS"
      }

  """
  def tin_validator(tin) do
    req_base()
    |> Req.get!(url: "identification/tin/" <> tin)
    |> Map.get(:body)
  end

  @doc """
  Validate National ID No.

  ## Examples

      iex> EvatMod.nationalid_validator("GHA-000XXXXXX-2")
      %{
        "data" => %{
          "name" => "name",
          "national_id" => "GHA-000XXXXXX-2",
          "nationality" => "GHANA",
          "sex" => "MALE"
        },
        "status" => "SUCCESS"
      }

  """
  def nationalid_validator(id) do
    req_base()
    |> Req.get!(url: "identification/nationalId/" <> id)
    |> Map.get(:body)
  end

  def get_invoice(invoice_id) do
    [invoice] =
      ExDbase.parse(
        "/home/hvaria/Documents/backup/MGP23/SIINV.DBF",
        [
          "IN_TP",
          "IN_NO",
          "IN_DT",
          "IN_PARTY",
          "IN_WRE",
          "IN_STK",
          "IN_CASH",
          "IN_CHQ",
          "IN_CREDIT",
          "IN_DET1",
          "IN_DET2",
          "IN_DET3",
          "IN_LMU",
          "IN_LMD",
          "IN_LMT"
        ],
        fn x ->
          id = to_invoice_id(x["IN_TP"], Integer.to_string(x["IN_NO"]))

          if id === invoice_id do
            %{
              id: id,
              date: to_date(x["IN_DT"]),
              customer_id: x["IN_PARTY"],
              price_level: nil?(x["IN_WRE"]),
              from_stock: nil?(x["IN_STK"]),
              cash: x["IN_CASH"],
              cheque: x["IN_CHQ"],
              credit: x["IN_CREDIT"],
              detail1: nil?(x["IN_DET1"]),
              detail2: nil?(:unicode.characters_to_binary(x["IN_DET2"], :latin1, :utf8)),
              detail3: nil?(x["IN_DET3"]),
              lmu: nil?(x["IN_LMU"]),
              lmt: to_timestamp(x["IN_LMD"], x["IN_LMT"])
            }
          else
            nil
          end
        end
      )

    details =
      ExDbase.parse(
        "/home/hvaria/Documents/backup/MGP23/SIDETINV.DBF",
        [
          "IN_TP",
          "IN_NO",
          "IN_DT",
          "IN_PARTY",
          "IN_WRE",
          "IN_STK",
          "IN_CASH",
          "IN_CHQ",
          "IN_CREDIT",
          "IN_DET1",
          "IN_DET2",
          "IN_DET3",
          "IN_LMU",
          "IN_LMD",
          "IN_LMT"
        ],
        fn x ->
          IO.inspect(x["IN_NO"])
          id = to_invoice_id(x["IN_TP"], Integer.to_string(x["IN_NO"]))

          if id === invoice_id do
            %{
              id: id,
              date: to_date(x["IN_DT"]),
              customer_id: x["IN_PARTY"],
              price_level: nil?(x["IN_WRE"]),
              from_stock: nil?(x["IN_STK"]),
              cash: x["IN_CASH"],
              cheque: x["IN_CHQ"],
              credit: x["IN_CREDIT"],
              detail1: nil?(x["IN_DET1"]),
              detail2: nil?(:unicode.characters_to_binary(x["IN_DET2"], :latin1, :utf8)),
              detail3: nil?(x["IN_DET3"]),
              lmu: nil?(x["IN_LMU"]),
              lmt: to_timestamp(x["IN_LMD"], x["IN_LMT"])
            }
          else
            nil
          end
        end
      )

    details
  end

  defp req_base() do
    Req.new(base_url: "https://vsdcstaging.vat-gh.com/vsdc/api/v1/taxpayer/CXX000000YY-001")
    |> Req.Request.put_new_header("security_key", "Z60gftKe9sei3xOZhvvDa0StkVILKR3j5MBM9ygi1zg=")
  end

  defp to_invoice_id(code, num) do
    code <> String.duplicate(" ", 9 - String.length(num)) <> num
  end

  @spec nil?(any()) :: any()
  def nil?(""), do: nil
  def nil?(string), do: string

  @spec default_date() :: Date.t()
  def default_date(), do: @default_date
  @spec default_time() :: Time.t()
  def default_time(), do: @default_time

  def to_timestamp(lmd, lmt) do
    {:ok, timestamp} = NaiveDateTime.new(to_date(lmd), to_time(lmt))
    timestamp
  end

  @spec to_date(<<_::_*64>>) :: Date.t()
  def to_date(<<y0, y1, y2, y3, m0, m1, d0, d1>>) do
    Date.from_iso8601!(<<y0, y1, y2, y3, "-", m0, m1, "-", d0, d1>>)
  end

  def to_date(""), do: @default_date
  def to_date(nil), do: @default_date

  @spec to_time(nil | binary()) :: Time.t()
  def to_time(""), do: @default_time
  def to_time(nil), do: @default_time
  def to_time(time), do: Time.from_iso8601!(time)
end
