# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # verify_signature! for the webhook: reads the signature from the header or the body, rebuilds
    # the message (raw body or concatenated values), computes the digest the spec names (HMAC or
    # plain, hex or base64) and compares in constant time. Every gap the spec leaves is filled
    # with the canon default and lowers the confidence written into the TODO marker.
    class SignatureVerifier
      HMAC = { "hmac-sha256" => "SHA256", "hmac-sha512" => "SHA512", "hmac-sha1" => "SHA1", "hmac-md5" => "MD5" }.freeze
      DIGEST = { "sha256" => "SHA256", "sha512" => "SHA512", "sha1" => "SHA1", "md5" => "MD5" }.freeze
      ASYMMETRIC = %w[rsa-sha256 ed25519].freeze
      CONCATENATED = "concatenated_fields"
      UNKNOWN = "unknown"

      def initialize(service, signature)
        @service = service
        @signature = signature
        @canon = service.canon
      end

      def method_data
        MethodData.build(name: "verify_signature!", params: "payload", comment: comment, lines: lines)
      end

      # "HMAC-SHA256" - the algorithm the code implements (canon default when the spec names none).
      def algorithm = (signature.algorithm == UNKNOWN ? default("algorithm") : signature.algorithm)
      def encoding = (signature.encoding == UNKNOWN ? default("encoding") : signature.encoding)
      def message = (signature.message == UNKNOWN ? default("message") : signature.message)

      # The confidence the TODO marker reports: the spec's, capped by every assumption made.
      def confidence
        caps = [signature.confidence]
        caps << Generator::Confidence::SIGNATURE_DEFAULTED if defaulted?
        caps << 0.5 if signature.algorithm == UNKNOWN || message == CONCATENATED
        caps << 0.4 if DIGEST.key?(algorithm)
        caps << 0.3 if ASYMMETRIC.include?(algorithm)
        caps.min
      end

      private

      attr_reader :service, :signature, :canon

      def default(name) = canon.signature_default(name)
      def defaulted? = signature.encoding == UNKNOWN || signature.message == UNKNOWN

      def comment
        described = message == "raw_body" ? "the raw request body" : "the payload values concatenated"
        lines = ["#{algorithm.upcase} over #{described}, #{encoding}, compared in constant time.",
                 "Evidence: #{signature.evidence.join("; ")}"]
        lines << Generator::Confidence.todo_if_needed(confidence, assumptions.join("; "))
        lines.compact
      end

      # One note per gap the spec leaves, in the order the caps of #confidence apply.
      def assumptions
        {
          defaulted? => "encoding and canonicalization are not in the spec (W301): #{encoding} over #{message} assumed",
          message == CONCATENATED => "field order of the signature base string is not in the spec; values sorted " \
                                     "by key assumed",
          DIGEST.key?(algorithm) => "how the secret is mixed into the digest is not in the spec; message + secret " \
                                    "assumed",
          ASYMMETRIC.include?(algorithm) => "asymmetric signature needs the provider public key",
          signature.algorithm == UNKNOWN => "algorithm not named in the spec; #{default("algorithm")} assumed"
        }.filter_map { |applies, note| note if applies }
      end

      def lines
        if ASYMMETRIC.include?(algorithm)
          message = Code.str("verify_signature!: #{algorithm} needs the provider public key")
          return ["raise NotImplementedError, #{message}"]
        end

        service.require("openssl")
        [signature_line, message_line, expected_line,
         "return if !signature.empty? && secure_compare(expected, signature)", "",
         "raise #{canon.exception("invalid_credentials")}, #{Code.str("invalid_signature")}"]
      end

      def signature_line
        source = if signature.location == "body"
                   Code.access("callback_body(payload)", signature.name)
                 else
                   "payload.dig(#{Code.str(canon.callback_key("headers"))}, #{Code.str(signature.name)})"
                 end
        "signature = #{source}.to_s"
      end

      def message_line
        if message == CONCATENATED
          "message = callback_body(payload).reject { |key, _| key == #{Code.str(signature.name)} }" \
            ".sort.map { |_, value| value.to_s }.join"
        else
          service.require("json")
          "message = payload[#{Code.str(canon.callback_key("raw_body"))}] || JSON.generate(callback_body(payload))"
        end
      end

      def expected_line
        secret = "#{canon.credential(canon.callback_secret_key)}.to_s"
        digest = Code.str(HMAC[algorithm] || DIGEST[algorithm] || HMAC.fetch(default("algorithm")))
        "expected = #{DIGEST.key?(algorithm) ? plain_digest(digest, secret) : hmac(digest, secret)}"
      end

      def hmac(digest, secret)
        return "OpenSSL::HMAC.hexdigest(#{digest}, #{secret}, message)" if encoding == "hex"

        "[OpenSSL::HMAC.digest(#{digest}, #{secret}, message)].pack('m0')"
      end

      def plain_digest(digest, secret)
        data = "\"\#{message}\#{#{secret}}\""
        return "OpenSSL::Digest.hexdigest(#{digest}, #{data})" if encoding == "hex"

        "[OpenSSL::Digest.digest(#{digest}, #{data})].pack('m0')"
      end
    end
  end
end
