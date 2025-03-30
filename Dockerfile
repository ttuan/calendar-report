FROM ruby:3.0-slim

# Set working directory
WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install

# Copy the rest of the application
COPY . .

# Expose port
EXPOSE 4567

# Set environment variables
ENV RACK_ENV=production

# Start the application
CMD ["ruby", "app.rb", "-o", "0.0.0.0"] 