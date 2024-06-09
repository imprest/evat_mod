defmodule EvatMod do
  @moduledoc """
  Documentation for `EvatMod`.
  """
  @default_date Date.from_iso8601!("2016-10-01")
  @default_time Time.from_iso8601!("08:00:00")
  alias Decimal, as: D

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

  def upload_invoice(invoice_id) do
    random_testing_id =
      (:rand.uniform() * 100_000) |> Float.to_string() |> String.split(".") |> hd

    invoice =
      get_invoice(invoice_id)
      |> Map.update!(
        :invoiceNumber,
        fn x -> x <> "-" <> random_testing_id end
      )

    invoice =
      invoice
      |> Map.update!(:totalAmount, &Decimal.to_float(&1))
      |> Map.update!(:totalLevy, &Decimal.to_float(&1))
      |> Map.update!(:totalVat, &Decimal.to_float(&1))
      |> Map.update!(:exchangeRate, &Decimal.to_float(&1))

    new_items =
      Map.get(invoice, :items)
      |> Enum.map(fn x ->
        x
        |> Map.update!(:quantity, &Decimal.to_float(&1))
        |> Map.update!(:unitPrice, &Decimal.to_float(&1))
        |> Map.update!(:levyAmountA, &Decimal.to_float(&1))
        |> Map.update!(:levyAmountB, &Decimal.to_float(&1))
        |> Map.update!(:levyAmountC, &Decimal.to_float(&1))
        |> Map.update!(:levyAmountD, &Decimal.to_float(&1))
        |> Map.update!(:levyAmountE, &Decimal.to_float(&1))
      end)

    invoice =
      Map.put(invoice, :items, new_items)

    IO.inspect(invoice)

    req_base()
    |> Req.post!(url: "invoice", json: invoice)
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
          "IN_TOT",
          "IN_CASH",
          "IN_CHQ",
          "IN_CREDIT",
          "IN_LMT",
          "IN_LMU"
        ],
        fn x ->
          id = to_invoice_id(x["IN_TP"], Integer.to_string(x["IN_NO"]))

          if id === invoice_id and
               x["IN_TOT"] === D.add(x["IN_CASH"], D.add(x["IN_CREDIT"], x["IN_CHQ"])) do
            %{
              customer_id: x["IN_PARTY"],
              calculationType: "INCLUSIVE",
              currency: "GHS",
              exchangeRate: Decimal.new("1.0"),
              flag: "INVOICE",
              invoiceNumber: id,
              saleType: "NORMAL",
              totalAmount: x["IN_TOT"],
              totalLevy: D.new(0),
              totalVat: D.new(0),
              transactionDate:
                Date.to_string(to_date(x["IN_DT"])) <>
                  "T" <> Time.to_string(to_time(x["IN_LMT"])) <> "Z",
              userName: nil?(x["IN_LMU"]),
              # Below fields to be dropped later
              cash: x["IN_CASH"],
              cheque: x["IN_CHQ"],
              credit: x["IN_CREDIT"]
            }
          else
            nil
          end
        end
      )

    items =
      ExDbase.parse(
        "/home/hvaria/Documents/backup/MGP23/SIDETINV.DBF",
        [
          "ID_NO",
          "ID_SRNO",
          "ID_ITM",
          "ID_DESC",
          "ID_QTY",
          "ID_RATE"
        ],
        fn x ->
          if x["ID_NO"] === invoice_id do
            %{
              itemCategory: "EXM",
              itemCode: x["ID_ITM"],
              description: x["ID_DESC"],
              quantity: x["ID_QTY"],
              # NHIL
              levyAmountA: D.new(0),
              # GETFUND
              levyAmountB: D.new(0),
              # COVID
              levyAmountC: D.new(0),
              # CST
              levyAmountD: D.new(0),
              # TOURISM
              levyAmountE: D.new(0),
              unitPrice: x["ID_RATE"]
            }
          else
            nil
          end
        end
      )

    [customer] =
      if D.compare(invoice.cash, invoice.totalAmount) === :eq do
        [
          %{
            businessPartnerName: "Cash Customer",
            businessPartnerTin: "C0000000000"
          }
        ]
      else
        ExDbase.parse(
          "/home/hvaria/Documents/backup/MGP23/FISLMST.DBF",
          [
            "SL_GLCD",
            "SL_CODE",
            "SL_DESC",
            "SL_STNO"
          ],
          fn x ->
            if x["SL_GLCD"] === "203000" and x["SL_CODE"] === invoice.customer_id do
              %{
                businessPartnerName: x["SL_DESC"],
                businessPartnerTin: "C0000000000"
                # businessPartnerTin: x["SL_STNO"]
              }
            else
              nil
            end
          end
        )
      end

    invoice = Map.put_new(invoice, :items, items)
    invoice = Map.merge(invoice, customer)

    # check invoice totalAmount is matching invoice items
    items_total =
      for x <- invoice.items, reduce: D.new(0) do
        acc ->
          D.add(acc, D.mult(x.quantity, x.unitPrice))
      end

    if D.compare(invoice.totalAmount, items_total) === :eq do
      invoice |> Map.drop([:cash, :cheque, :credit])
    else
      "Invoice total does not match invoice items total"
    end
  end

  def get_customers_data() do
    ExDbase.parse(
      "/home/hvaria/Documents/backup/MGP23/FISLMST.DBF",
      [
        "SL_GLCD",
        "SL_CODE",
        "SL_DESC",
        "SL_STNO"
      ],
      fn x ->
        if x["SL_GLCD"] === "203000" do
          %{
            code: x["SL_CODE"],
            businessPartnerName: x["SL_DESC"],
            businessPartnerTin: x["SL_STNO"]
          }
        else
          nil
        end
      end
    )
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
