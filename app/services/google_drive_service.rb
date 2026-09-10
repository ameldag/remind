require 'google/apis/drive_v3'
require 'googleauth'

class GoogleDriveService
  
  SUPPORTED_MIMES = [
    # PDF
    'application/pdf',
  
    # Google Docs
    'application/vnd.google-apps.document',
  
    # DOCX
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  
    # Text
    'text/plain',
  
    # Images
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp'
  ].freeze

  def initialize
    @service = Google::Apis::DriveV3::DriveService.new
    @service.authorization = credentials
  end
  
  def list_files(since: nil)
    mime_query = SUPPORTED_MIMES.map { |m| "mimeType='#{m}'" }.join(" or ")
    query      = "(#{mime_query}) and trashed=false"
    query     += " and modifiedTime > '#{since.iso8601}'" if since

    files      = []
    page_token = nil

    loop do
      resp = @service.list_files(
        q:           query,
        fields:      "nextPageToken, files(id, name, mimeType, modifiedTime, webViewLink, driveId)",
        page_token:  page_token,
        page_size:   100,
        order_by:    "modifiedTime desc",
        # params: "include_items_from_all_drives" & "supports_all_drives" for shared Drives
        include_items_from_all_drives: true,
        supports_all_drives: true
      )
      files     += resp.files
      page_token = resp.next_page_token
      break unless page_token
    end

    files
  end

  def extract_text(file)
    
    case file.mime_type
    when "application/vnd.google-apps.document"
      content = @service.files().export(
                fileId=file.id,
                mimeType='text/plain'
            ).execute()
      content.force_encoding("UTF-8")

    when "application/pdf"
      data = download_file(file.id)
      reader = PDF::Reader.new(StringIO.new(data))
      reader.pages.map(&:text).join("\n")

    when /wordprocessingml/
      data = download_file(file.id)
      doc  = Docx::Document.open(StringIO.new(data))
      doc.paragraphs.map(&:to_s).join("\n")

    when "text/plain"
      download_file(file.id).force_encoding("UTF-8")
    end
  rescue => e
    Rails.logger.error "Erreur extraction #{file.name}: #{e.message}"
    nil
  end

  private

  def download_file(file_id)
    buffer = StringIO.new
    @service.get_file(file_id, download_dest: buffer, supports_all_drives: true) # param: "supports_all_drives" for shared Drives
    buffer.string
  end

  def credentials
    Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['CLIENT_ID'],
      client_secret: ENV['CLIENT_SECRET'],
      refresh_token: ENV['REFRESH_TOKEN'],
      project_id: ENV['PROJECT_ID'],
      scope: ['https://www.googleapis.com/auth/drive.readonly'],
      redirect_uris: [ENV['REDIRECT_URIS']]
    )
  end
end
