# app/services/sants_withdraw_service.rb
require "net/http"
require "json"
require "uri"

class SantsWithdrawService
  BASE_URL      = ENV["SANTS_PIX_API_BASE_URL"] || "https://api.pix.santsbank.com.br"
  WITHDRAW_PATH = ENV["SANTS_PIX_WITHDRAW_PATH"] || "/pix/v1/transferir"

  CLIENT_ID     = ENV["SANTS_PIX_CLIENT_ID"]
  CLIENT_SECRET = ENV["SANTS_PIX_CLIENT_SECRET"]
  AUTH_PATH     = ENV["SANTS_PIX_AUTH_PATH"] || "/no-auth/autenticacao/v1/api/login"

  WEBHOOK_TOKEN = ENV["SANTS_WEBHOOK_TOKEN"]
  SANTS_TOKEN   = ENV["SANTS_TOKEN"]

  def initialize
    @base_url = BASE_URL
  end

  def withdraw(amount_cents:, pix_key:, pix_key_type: "CPF")
    auth_result = authenticate_token

    if auth_result.is_a?(Hash)
      Rails.logger.error "[SantsWithdrawService] Erro na autenticação: #{auth_result.inspect}"
      return {
        "sucesso"  => false,
        "mensagem" => auth_result["error"] || "Falha na autenticação Sants"
      }
    end

    access_token = auth_result.to_s
    id_envio     = SecureRandom.uuid[0, 36]

    payload = {
      idEnvio:         id_envio,
      valor:           amount_cents.to_i, # centavos
      chavePixDestino: pix_key.to_s.strip
      # tipoChaveDestino: pix_key_type
    }

    uri = URI.join(@base_url, WITHDRAW_PATH)

    Rails.logger.info "[SantsWithdrawService] Request POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{access_token}"
    request["Token"]         = SANTS_TOKEN if SANTS_TOKEN.present?

    request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[SantsWithdrawService] Response #{response.code} #{uri} - body: #{response.body}"

    body      = JSON.parse(response.body) rescue {}
    http_code = response.code.to_i

    if [401, 403].include?(http_code)
      msg = body["mensagem"] ||
            body["message"]  ||
            body.dig("erro", "motivo") ||
            body.dig("erro", "mensagem") ||
            "Acesso não autorizado/forbidden na API Sants (HTTP #{http_code})"

      Rails.logger.error "[SantsWithdrawService] HTTP #{http_code} ao enviar saque: #{msg} - body=#{body.inspect}"

      return {
        "sucesso"      => false,
        "mensagem"     => msg,
        "http_status"  => http_code,
        "raw_response" => body
      }
    end

    if http_code == 200 && body["sucesso"] == true
      {
        "sucesso"           => true,
        "mensagem"          => body["mensagem"],
        "codigoTransacao"   => body["codigoTransacao"],
        "dataHoraTransacao" => body["dataHoraTransacao"]
      }
    else
      msg = body["mensagem"] ||
            body["message"]  ||
            body.dig("erro", "motivo") ||
            body.dig("erro", "mensagem") ||
            "Erro ao solicitar saque na Sants"

      Rails.logger.error "[SantsWithdrawService] Falha no saque: HTTP #{http_code} msg=#{msg} body=#{body.inspect}"

      {
        "sucesso"      => false,
        "mensagem"     => msg,
        "http_status"  => http_code,
        "raw_response" => body
      }
    end
  rescue => e
    Rails.logger.error "[SantsWithdrawService] Erro em withdraw: #{e.class} - #{e.message}"
    {
      "sucesso"  => false,
      "mensagem" => "Erro interno ao chamar API Sants: #{e.message}"
    }
  end

  private

  def authenticate_token
    if CLIENT_ID.blank? || CLIENT_SECRET.blank?
      msg = "CLIENT_ID/CLIENT_SECRET da Sants não configurados (ENV SANTS_PIX_CLIENT_ID / SANTS_PIX_CLIENT_SECRET)"
      Rails.logger.error "[SantsWithdrawService] #{msg}"
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

    Rails.logger.info "[SantsWithdrawService] Auth POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Token"]        = SANTS_TOKEN if SANTS_TOKEN.present?

    request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[SantsWithdrawService] Auth response #{response.code} - body: #{response.body}"

    body = JSON.parse(response.body) rescue {}
    Rails.logger.info "[SantsWithdrawService] Auth parsed body: #{body.inspect}"

    if response.code.to_i == 200 && body["sucesso"] == true && body["accessToken"].present?
      access_token = body["accessToken"].to_s
      Rails.logger.info "[SantsWithdrawService] Auth OK, token recebido (tamanho=#{access_token.size})"
      access_token
    else
      msg = body["mensagem"] || body["message"] || "Falha ao autenticar na API Sants"
      Rails.logger.error "[SantsWithdrawService] Auth FAIL: HTTP #{response.code} msg=#{msg} body=#{body.inspect}"

      {
        "status"      => false,
        "error"       => msg,
        "raw"         => body,
        "http_status" => response.code.to_i
      }
    end
  rescue => e
    Rails.logger.error "[SantsWithdrawService] Erro em authenticate_token: #{e.class} - #{e.message}"
    {
      "status" => false,
      "error"  => "Erro interno na autenticação Sants: #{e.message}"
    }
  end
end
