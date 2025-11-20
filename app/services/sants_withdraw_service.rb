# app/services/sants_withdraw_service.rb
require "net/http"
require "json"
require "uri"

class SantsWithdrawService
  BASE_URL      = ENV["SANTS_PIX_API_BASE_URL"] || "https://api.pix.santsbank.com.br"
  WEBHOOK_TOKEN = ENV["SANTS_WEBHOOK_TOKEN"]

  def initialize
    @base_url = BASE_URL
  end

  # -----------------------------------------------------------
  # Faz a transferência PIX (saque) via Sants
  # amount_cents: valor em centavos (positivo)
  # pix_key: chave PIX destino (cpf/cnpj/email/telefone/aleatória)
  # pix_key_type: tipo da chave (CPF, CNPJ, PHONE, EMAIL, EVP)
  # -----------------------------------------------------------
  def withdraw(amount_cents:, pix_key:, pix_key_type: nil)
    raw_pix_key = pix_key.to_s

    sanitized_pix_key =
      case pix_key_type.to_s.upcase
      when "CPF", "CNPJ"
        raw_pix_key.gsub(/[^\d]/, "")
      when "PHONE"
        digits = raw_pix_key.gsub(/[^\d]/, "")
        digits = "55#{digits}" unless digits.start_with?("55")
        "+#{digits}"
      when "EMAIL"
        raw_pix_key.strip
      when "EVP"
        raw_pix_key.upcase.strip.gsub(/[^A-Z0-9-]/, "")
      else
        raw_pix_key.strip
      end

    Rails.logger.info "[SantsWithdrawService] usando chave PIX saneada: #{sanitized_pix_key} (tipo=#{pix_key_type})"

    auth_result = SantsPixService.new.authenticate

    if auth_result.is_a?(Hash)
      return {
        "sucesso"  => false,
        "mensagem" => auth_result["error"] || "Falha na autenticação Liquidante"
      }
    end

    access_token = auth_result
    id_envio     = SecureRandom.uuid[0, 36]

    payload = {
      idEnvio:         id_envio,
      valor:           amount_cents.to_i,
      chavePixDestino: sanitized_pix_key
    }

    uri = URI.join(@base_url, "/pix/v1/transferir")

    Rails.logger.info "[SantsWithdrawService] Request POST #{uri} - body: #{payload.inspect}"

    request = Net::HTTP::Post.new(uri)
    request["Accept"]        = "application/json"
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{access_token}"
    request["Token"]         = WEBHOOK_TOKEN if WEBHOOK_TOKEN.present?
    request.body             = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    Rails.logger.info "[SantsWithdrawService] Response #{response.code} #{uri} - body: #{response.body}"

    JSON.parse(response.body) rescue {
      "sucesso"  => false,
      "mensagem" => "Erro ao interpretar resposta da Liquidante"
    }
  rescue => e
    Rails.logger.error "[SantsWithdrawService] Erro em withdraw: #{e.class} - #{e.message}"
    {
      "sucesso"  => false,
      "mensagem" => "Erro interno na chamada de saque Liquidante: #{e.message}"
    }
  end
end
