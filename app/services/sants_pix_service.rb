require "net/http"
require "json"
require "uri"

class SantsPixService
  BASE_URL      = ENV["SANTS_PIX_API_BASE_URL"] || "https://api.pix.santsbank.com.br"
  CLIENT_ID     = ENV["SANTS_PIX_CLIENT_ID"]
  CLIENT_SECRET = ENV["SANTS_PIX_CLIENT_SECRET"]

  AUTH_PATH     = ENV["SANTS_PIX_AUTH_PATH"]   || "/no-auth/autenticacao/v1/api/login"
  QRCODE_PATH   = ENV["SANTS_PIX_QRCODE_PATH"] || "/qrcode/v2/gerar"
  DEFAULT_EXP   = (ENV["SANTS_PIX_DEFAULT_EXPIRATION"] || 600).to_i

  WEBHOOK_TOKEN = ENV["SANTS_WEBHOOK_TOKEN"]

  def initialize
    @base_url = BASE_URL
  end

  # =========================================
  # Autenticação
  # =========================================
  def authenticate
    uri = URI.join(@base_url, AUTH_PATH)

    payload = {
      clientId:     CLIENT_ID,
      clientSecret: CLIENT_SECRET
    }

    Rails.logger.info "[SantsPixService] Auth POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body            = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[SantsPixService] Auth response #{response.code} - body: #{response.body}"

    body = JSON.parse(response.body) rescue {}

    if response.code.to_i == 200 && body["sucesso"] == true && body["accessToken"].present?
      body["accessToken"]
    else
      msg = body["mensagem"] || body["message"] || "Falha ao autenticar na API Sants"
      {
        "status" => false,
        "error"  => msg,
        "raw"    => body
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
  # =========================================
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

    access_token = authenticate
    return access_token if access_token.is_a?(Hash) # erro de auth

    valor = amount_cents.to_i

    payload = {
      valor:          valor,
      tempoExpiracao: expiration_seconds,
      comImagem:      true
    }
    payload[:informacaoAdicional] = info if info.present?

    uri = URI.join(@base_url, QRCODE_PATH)
    Rails.logger.info "[SantsPixService] Request POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request["Accept"]        = "application/json"
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{access_token}"
    request["Token"]         = WEBHOOK_TOKEN if WEBHOOK_TOKEN.present?
    request.body             = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[SantsPixService] Response #{response.code} #{uri} - body: #{response.body}"

    body = JSON.parse(response.body) rescue {}

    if response.code.to_i == 200 && body["sucesso"] == true
      # Sants pode mandar "txId" ou "txid" dependendo do endpoint
      tx_id  = body["txId"] || body["txid"]
      qrcode = body["qrcode"] || {}

      unless tx_id.present?
        Rails.logger.warn "[SantsPixService] tx_id não encontrado no body: #{body.inspect}"
      end

      {
        "status"  => true,
        "message" => body["mensagem"],
        "data"    => {
          "id"        => tx_id,           # 👈 é isso que vira gateway_id na PixTransaction
          "amount"    => amount_cents,    # interno sempre em centavos
          "feeAmount" => 0,
          "status"    => "PENDING",
          "pix"       => {
            "qrcode"    => qrcode["imagem"], # base64 da imagem
            "copyPaste" => qrcode["emv"]     # EMV copia e cola
          }
        }
      }
    else
      msg = body["mensagem"] || body["message"] || "Erro ao criar QRCode Sants"
      {
        "status" => false,
        "error"  => msg,
        "raw"    => body
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
