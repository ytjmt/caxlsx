# encoding: UTF-8
require 'htmlentities'
require 'axlsx/version.rb'
require 'marcel'

require 'axlsx/util/simple_typed_list.rb'
require 'axlsx/util/constants.rb'
require 'axlsx/util/validators.rb'
require 'axlsx/util/accessors.rb'
require 'axlsx/util/serialized_attributes'
require 'axlsx/util/options_parser'
require 'axlsx/util/mime_type_utils'
require 'axlsx/util/zip_command'

require 'axlsx/stylesheet/styles.rb'

require 'axlsx/doc_props/app.rb'
require 'axlsx/doc_props/core.rb'
require 'axlsx/content_type/content_type.rb'
require 'axlsx/rels/relationships.rb'

require 'axlsx/drawing/drawing.rb'
require 'axlsx/workbook/workbook.rb'
require 'axlsx/package.rb'
#required gems
require 'nokogiri'
require 'zip'

#core dependencies
require 'bigdecimal'
require 'time'

# xlsx generation with charts, images, automated column width, customizable styles
# and full schema validation. Axlsx excels at helping you generate beautiful
# Office Open XML Spreadsheet documents without having to understand the entire
# ECMA specification. Check out the README for some examples of how easy it is.
# Best of all, you can validate your xlsx file before serialization so you know
# for sure that anything generated is going to load on your client's machine.
module Axlsx
  # I am a very big fan of activesupports instance_values method, but do not want to require nor include the entire
  # library just for this one method.
  #
  # Defining as a class method on Axlsx to refrain from monkeypatching Object for all users of this gem.
  def self.instance_values_for(object)
    Hash[object.instance_variables.map { |name| [name.to_s[1..-1], object.instance_variable_get(name)] }]
  end

  # determines the cell range for the items provided
  def self.cell_range(cells, absolute=true)
    return "" unless cells.first.is_a? Cell

    first_cell, last_cell = cells.minmax_by(&:pos)
    reference = "#{first_cell.reference(absolute)}:#{last_cell.reference(absolute)}"
    if absolute
      escaped_name = first_cell.row.worksheet.name.gsub '&apos;', "''"
      "'#{escaped_name}'!#{reference}"
    else
      reference
    end
  end

  # sorts the array of cells provided to start from the minimum x,y to
  # the maximum x.y#
  # @param [Array] cells
  # @return [Array]
  def self.sort_cells(cells)
    cells.sort_by(&:pos)
  end

  #global reference html entity encoding
  # @return [HtmlEntities]
  def self.coder
    @@coder ||= ::HTMLEntities.new
  end

  # returns the x, y position of a cell
  def self.name_to_indices(name)
    raise ArgumentError, 'invalid cell name' unless name.size > 1

    letters_str = name[/[A-Z]+/]

    # capitalization?!?
    v = letters_str.reverse.chars.reduce({:base=>1, :i=>0}) do  |val, c|
      val[:i] += ((c.bytes.first - 64) * val[:base])

      val[:base] *= 26

      next val
    end

    col_index = (v[:i] - 1)

    numbers_str = name[/[1-9][0-9]*/]

    row_index = (numbers_str.to_i - 1)

    return [col_index, row_index]
  end

  # converts the column index into alphabetical values.
  # @note This follows the standard spreadsheet convention of naming columns A to Z, followed by AA to AZ etc.
  # @return [String]
  def self.col_ref(index)
    chars = ''
    while index >= 26 do
      index, char = index.divmod(26)
      chars.prepend((char + 65).chr)
      index -= 1
    end
    chars.prepend((index + 65).chr)
    chars
  end

  # @return [String] The alpha(column)numeric(row) reference for this sell.
  # @example Relative Cell Reference
  #   ws.rows.first.cells.first.r #=> "A1"
  def self.cell_r(c_index, r_index)
    col_ref(c_index) << (r_index+1).to_s
  end

  # Creates an array of individual cell references based on an excel reference range.
  # @param [String] range A cell range, for example A1:D5
  # @return [Array]
  def self.range_to_a(range)
    range.match(/^(\w+?\d+)\:(\w+?\d+)$/)
    start_col, start_row = name_to_indices($1)
    end_col,   end_row   = name_to_indices($2)
    (start_row..end_row).to_a.map do |row_num|
      (start_col..end_col).to_a.map do |col_num|
        cell_r(col_num, row_num)
      end
    end
  end

  # performs the increadible feat of changing snake_case to CamelCase
  # @param [String] s The snake case string to camelize
  # @return [String]
  def self.camel(s="", all_caps = true)
    s = s.to_s
    s = s.capitalize if all_caps
    s.gsub(/_(.)/){ $1.upcase }
  end

  # returns the provided string with all invalid control charaters
  # removed.
  # @param [String] str The string to process
  # @return [String]
  def self.sanitize(str)
    if str.frozen?
      str.delete(CONTROL_CHARS)
    else
      str.delete!(CONTROL_CHARS)
      str
    end
  end

  # If value is boolean return 1 or 0
  # else return the value
  # @param [Object] value The value to process
  # @return [Object]
  def self.booleanize(value)
    if value == true || value == false
      value ? 1 : 0
    else
      value
    end
  end

  # Instructs the serializer to not try to escape cell value input.
  # This will give you a huge speed bonus, but if you content has <, > or other xml character data
  # the workbook will be invalid and excel will complain.
  def self.trust_input
    @trust_input ||= false
  end

  # @param[Boolean] trust_me A boolean value indicating if the cell value content is to be trusted
  # @return [Boolean]
  # @see Axlsx::trust_input
  def self.trust_input=(trust_me)
    @trust_input = trust_me
  end
end
