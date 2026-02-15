module RedmineSubwikifiles
  # Utility class to check if a file is being accessed or locked by an external process.
  class FileLockChecker
    # Check if a file is currently locked/opened by another process
    # 
    # @param file_path [String] Absolute path to the file to check
    # @return [Boolean] true if file is locked, false otherwise
    def self.locked?(file_path)
      return false unless File.exist?(file_path)
      
      File.open(file_path, 'r') do |file|
        # Try to get exclusive lock (non-blocking)
        # Returns false if lock acquired, true if would block
        !file.flock(File::LOCK_EX | File::LOCK_NB)
      end
    rescue Errno::EWOULDBLOCK
      # File is locked by another process
      true
    rescue => e
      # Log error but assume file is not locked
      Rails.logger.warn "RedmineSubwikifiles::FileLockChecker: Error checking lock for #{file_path}: #{e.message}"
      false
    end
  end
end
