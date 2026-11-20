# frozen_string_literal: true

require "base64"

module OpenProject
  module EntraId
    ##
    # Convierte una imagen subida en un data URI para guardarla en la
    # configuración del plugin. El tipo se detecta por el contenido (no por la
    # extensión ni por lo que diga el navegador).
    #
    # Se muestra siempre dentro de <img>, por lo que un SVG no puede ejecutar
    # scripts; aun así se rechazan SVG con <script>, manejadores on* o
    # referencias externas.
    module LogoUpload
      MAX_BYTES = 100 * 1024

      class Invalid < OpenProject::EntraId::Error; end

      module_function

      def to_data_uri(bytes)
        bytes = bytes.to_s.b
        raise Invalid, :logo_empty if bytes.empty?
        raise Invalid, :logo_too_big if bytes.bytesize > MAX_BYTES

        mime = detect(bytes)
        raise Invalid, :logo_bad_type unless mime
        raise Invalid, :logo_unsafe_svg if mime == "image/svg+xml" && unsafe_svg?(bytes)

        "data:#{mime};base64,#{Base64.strict_encode64(bytes)}"
      end

      def detect(bytes)
        return "image/png" if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
        return "image/jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)
        return "image/gif" if bytes.start_with?("GIF87a", "GIF89a")
        return "image/webp" if bytes[0, 4] == "RIFF" && bytes[8, 4] == "WEBP"

        text = bytes.dup.force_encoding(Encoding::UTF_8)
        return nil unless text.valid_encoding?

        head = text.lstrip.sub(/\A﻿/, "")
        "image/svg+xml" if head.match?(/\A(<\?xml[^>]*>\s*)?(<!--.*?-->\s*)*(<!DOCTYPE[^>]*>\s*)?<svg[\s>]/mi)
      end

      def unsafe_svg?(bytes)
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        text.match?(/<script|<foreignObject|\son[a-z]+\s*=|javascript:|<!ENTITY|(?:xlink:)?href\s*=\s*["']\s*(?!#|data:image\/)/i)
      end
    end
  end
end
