# app/services/sants_pix_service.rb
require "net/http"
require "json"
require "uri"

class SantsPixService
  BASE_URL      = ENV["SANTS_PIX_API_BASE_URL"] || "https://api.pix.santsbank.com.br"
  CLIENT_ID     = ENV["SANTS_PIX_CLIENT_ID"]
  CLIENT_SECRET = ENV["SANTS_PIX_CLIENT_SECRET"]
  SANTS_TOKEN   = ENV["SANTS_TOKEN"]

  AUTH_PATH     = ENV["SANTS_PIX_AUTH_PATH"]   || "/no-auth/autenticacao/v1/api/login"
  QRCODE_PATH   = ENV["SANTS_PIX_QRCODE_PATH"] || "/qrcode/v2/gerar"
  DEFAULT_EXP   = (ENV["SANTS_PIX_DEFAULT_EXPIRATION"] || 600).to_i

  # Token usado apenas pra validar o WEBHOOK (campo "token" no payload)
  WEBHOOK_TOKEN = ENV["SANTS_WEBHOOK_TOKEN"]

  def initialize
    @base_url = BASE_URL
  end

  # =========================================
  # Autenticação
  # =========================================
  def authenticate
    if CLIENT_ID.blank? || CLIENT_SECRET.blank?
      msg = "CLIENT_ID/CLIENT_SECRET da Sants não configurados (ENV SANTS_PIX_CLIENT_ID / SANTS_PIX_CLIENT_SECRET)"
      Rails.logger.error "[SantsPixService] #{msg}"
      return {
        "status" => false,
        "error"  => msg
      }
    end

    uri = URI.join(@base_url, AUTH_PATH)

    payload = {
      clientId:     CLIENT_ID,
      clientSecret: CLIENT_SECRET
    }

    Rails.logger.info "[SantsPixService] Auth POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    # Header Token com o valor do SANTS_TOKEN
    if SANTS_TOKEN.present?
      request["Token"] = SANTS_TOKEN
    else
      Rails.logger.warn "[SantsPixService] SANTS_TOKEN vazio; Auth sem header Token"
    end

    request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[SantsPixService] Auth response #{response.code} - body: #{response.body}"

    body = JSON.parse(response.body) rescue {}
    Rails.logger.info "[SantsPixService] Auth parsed body: #{body.inspect}"

    if response.code.to_i == 200 && body["sucesso"] == true && body["accessToken"].present?
      access_token = body["accessToken"].to_s
      Rails.logger.info "[SantsPixService] Auth OK, token recebido (tamanho=#{access_token.size})"
      access_token
    else
      msg = body["mensagem"] || body["message"] || "Falha ao autenticar na API Sants"
      Rails.logger.error "[SantsPixService] Auth FAIL: HTTP #{response.code} msg=#{msg} body=#{body.inspect}"

      {
        "status"      => false,
        "error"       => msg,
        "raw"         => body,
        "http_status" => response.code.to_i
      }
    end
  rescue => e
    Rails.logger.error "[SantsPixService] Erro em authenticate: #{e.class} - #{e.message}"
    {
      "status" => false,
      "error"  => "Erro interno na autenticação Sants: #{e.message}"
    }
  end

  # =========================================
  # Criar transação PIX (QRCode)
  # attrs:
  #   :amount             (em centavos)
  #   :expiration_seconds
  #   :info
  # =========================================
  def create_transaction(attrs)
    amount_cents       = attrs[:amount].to_i
    expiration_seconds = (attrs[:expiration_seconds] || DEFAULT_EXP).to_i
    info               = attrs[:info]

    if amount_cents <= 0
      return { "status" => false, "error" => "O valor tem que ser maior que zero" }
    end

    # ==============================
    # 1) Autenticação
    # ==============================
    access_token_result = authenticate

    if access_token_result.is_a?(Hash)
      Rails.logger.error "[SantsPixService] Abortando create_transaction por erro de auth: #{access_token_result.inspect}"
      return access_token_result
    end

    access_token = access_token_result.to_s
    Rails.logger.info "[SantsPixService] Usando access_token (len=#{access_token.size})"

    # Sants: valor em centavos ("valor": 500)
    valor = amount_cents.to_i

    payload = {
      valor:          valor,
      tempoExpiracao: expiration_seconds,
      comImagem:      true
    }
    payload[:informacaoAdicional] = info if info.present?

    uri = URI.join(@base_url, QRCODE_PATH)
    Rails.logger.info "[SantsPixService] Request POST #{uri} - body: #{payload.inspect}"
    Rails.logger.info "[SantsPixService] Request headers: Authorization='Bearer *****', Token='*****'"

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{access_token}"
    request["Token"]         = SANTS_TOKEN if SANTS_TOKEN.present?

    request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[SantsPixService] Response #{response.code} #{uri} - body: #{response.body}"

    body      = JSON.parse(response.body) rescue {}
    http_code = response.code.to_i

    # ==============================
    # 2) Tratamento explícito 401/403
    # ==============================
    if [401, 403].include?(http_code)
      msg = body["mensagem"] ||
            body["message"]  ||
            body.dig("erro", "motivo") ||
            body.dig("erro", "mensagem") ||
            "Acesso não autorizado/forbidden na API Sants (HTTP #{http_code})"

      Rails.logger.error "[SantsPixService] HTTP #{http_code} ao gerar QRCode: #{msg} - body=#{body.inspect}"

      return {
        "status"      => false,
        "error"       => msg,
        "raw"         => body,
        "http_status" => http_code
      }
    end

    # ==============================
    # 3) Sucesso "normal"
    # ==============================
    if http_code == 200 && body["sucesso"] == true
      tx_id  = body["txId"] || body["txid"]
      qrcode = body["qrcode"] || {}

      unless tx_id.present?
        Rails.logger.warn "[SantsPixService] tx_id não encontrado no body: #{body.inspect}"
      end

      {
        "status"  => true,
        "message" => body["mensagem"],
        "data"    => {
          "id"        => tx_id,
          "amount"    => amount_cents,
          "feeAmount" => 0,
          "status"    => "PENDING",
          "pix"       => {
            "qrcode"    => qrcode["imagem"],
            "copyPaste" => qrcode["emv"]
          }
        }
      }
    else
      msg = body["mensagem"] ||
            body["message"]  ||
            body.dig("erro", "motivo") ||
            body.dig("erro", "mensagem") ||
            "Erro ao criar QRCode Sants"

      Rails.logger.error "[SantsPixService] Falha ao criar QRCode: HTTP #{http_code} msg=#{msg} body=#{body.inspect}"

      {
        "status"      => false,
        "error"       => msg,
        "raw"         => body,
        "http_status" => http_code
      }
    end
  rescue => e
    Rails.logger.error "[SantsPixService] Erro em create_transaction: #{e.class} - #{e.message}"
    {
      "status" => false,
      "error"  => "Erro interno ao chamar API Sants: #{e.message}"
    }
  end
end
