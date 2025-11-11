FROM ruby:3.2.3

# Dependências do sistema
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  nodejs \
  yarn \
  && rm -rf /var/lib/apt/lists/*

# Pasta de trabalho da aplicação
WORKDIR /app

# Copia Gemfile e Gemfile.lock primeiro (para cache de bundle no build)
COPY Gemfile Gemfile.lock ./

# Instala as gems no build da imagem
RUN bundle install

# Copia todo o código do projeto
COPY . .

# Variáveis de ambiente padrão
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true

# Porta padrão do Rails/Puma
EXPOSE 3000

# Comando default (pode ser sobrescrito pelo docker-compose, como estamos fazendo)
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
