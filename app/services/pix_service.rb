# app/services/pix_service.rb
require 'net/http'
require 'json'
require 'uri'

class PixService
  BASE_URL = ENV['PIX_API_BASE_URL'] || 'https://api.witetec.net'
  API_KEY  = ENV['PIX_API_KEY']      || 'sk_3332d7fc778c08fb57c68fa531a43851884d5094f15b6106'

  def initialize
    @base_url = BASE_URL
    @api_key  = API_KEY
  end

  # -------------------------------------------------
  # Criar saque (withdrawal via PIX)
  # -------------------------------------------------
  # attrs:
  #   :amount_cents, :pix_key, :pix_key_type, :seller_external_ref
  # -------------------------------------------------
  def create_withdrawal(attrs)
    metadata = {}
    metadata[:sellerExternalRef] = attrs[:seller_external_ref] if attrs[:seller_external_ref].present?

    payload = {
      amount:     attrs[:amount_cents].to_i,
      pixKey:     attrs[:pix_key],
      pixKeyType: attrs[:pix_key_type] || "CPF",
      method:     "PIX"
    }
    payload[:metadata] = metadata unless metadata.empty?

    uri = URI("#{@base_url}/withdrawals")
    Rails.logger.info "[PixService] Request POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["x-api-key"]    = @api_key
    request.body            = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[PixService] Response #{response.code} #{uri} - body: #{response.body}"
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error "[PixService] Erro em create_withdrawal: #{e.class} - #{e.message}"
    { "status" => false, "error" => "Erro na comunicação com a API de Withdrawals" }
  end

  # -------------------------------------------------
  # Criar transação PIX
  # -------------------------------------------------
  # attrs:
  #   :amount, :customer_name, :customer_email, :customer_phone,
  #   :customer_document, :customer_document_type, :items (array)
  # -------------------------------------------------
  def create_transaction(attrs)
    payload = {
      amount: attrs[:amount].to_i,
      method: "PIX",
      customer: {
        name:         attrs[:customer_name],
        email:        attrs[:customer_email],
        phone:        attrs[:customer_phone],
        documentType: attrs[:customer_document_type] || "CPF",
        document:     attrs[:customer_document]      || "00000000000"
      },
      items: attrs[:items] || []
    }

    uri = URI("#{@base_url}/transactions")
    Rails.logger.info "[PixService] Request POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['x-api-key']    = @api_key
    request.body            = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    Rails.logger.info "[PixService] Response #{response.code} #{uri} - body: #{response.body}"

    JSON.parse(response.body)
  rescue JSON::ParserError
    { "status" => false, "error" => "Erro ao interpretar a resposta JSON da API" }
  rescue => e
    Rails.logger.error "[PixService] Erro ao criar PIX: #{e.class} - #{e.message}"
    { "status" => false, "error" => "Erro interno ao chamar API: #{e.message}" }
  end

  # -------------------------------------------------
  # Listar transações
  # -------------------------------------------------
  def get_transactions(_user_id = nil)
    uri = URI("#{@base_url}/transactions")

    request = Net::HTTP::Get.new(uri)
    request['x-api-key'] = @api_key

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    Rails.logger.info "[PixService] GET /transactions => #{response.code} #{response.body}"

    parsed = JSON.parse(response.body) rescue nil
    if parsed.is_a?(Hash) && parsed["data"].is_a?(Array)
      parsed["data"]
    elsif parsed.is_a?(Array)
      parsed
    else
      []
    end
  rescue => e
    Rails.logger.error "[PixService] Erro ao listar transações: #{e.class} - #{e.message}"
    []
  end

  # -------------------------------------------------
  # Saldo da carteira (seller wallet)
  # -------------------------------------------------
  def get_balance
    uri = URI("#{@base_url}/seller-wallet/balance")

    request = Net::HTTP::Get.new(uri)
    request['x-api-key'] = @api_key

    Rails.logger.info "[PixService] Request GET #{uri}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    Rails.logger.info "[PixService] Response #{response.code} #{uri} - body: #{response.body}"
    JSON.parse(response.body)
  rescue JSON::ParserError
    { "status" => false, "error" => "Erro ao interpretar JSON de /seller-wallet/balance" }
  rescue => e
    Rails.logger.error "[PixService] Erro ao buscar saldo: #{e.class} - #{e.message}"
    { "status" => false, "error" => e.message }
  end
end
