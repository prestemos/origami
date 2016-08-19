=begin

    This file is part of Origami, PDF manipulation framework for Ruby
    Copyright (C) 2016	Guillaume Delugré.

    Origami is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Origami is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with Origami.  If not, see <http://www.gnu.org/licenses/>.

=end


require 'origami/parsers/pdf'

module Origami

    class PDF

        #
        # Create a new PDF lazy Parser.
        #
        class LazyParser < Parser
            def parse(stream)
                super

                pdf = parse_initialize
                revisions = []

                # Set the scanner position at the end.
                @data.terminate

                # Locate the startxref token.
                until @data.match?(/#{Trailer::XREF_TOKEN}/)
                    raise ParsingError, "No xref token found" if @data.pos == 0
                    @data.pos -= 1
                end

                # Extract the offset of the last xref section.
                trailer = Trailer.parse(@data, self)
                raise ParsingError, "Cannot locate xref section" if trailer.startxref.zero?

                xref_offset = trailer.startxref
                while xref_offset and xref_offset != 0

                    # Create a new revision based on the xref section offset.
                    revision = parse_revision(pdf, xref_offset)

                    # Locate the previous xref section.
                    if revision.xrefstm
                        xref_offset = revision.xrefstm[:Prev].to_i
                    else
                        xref_offset = revision.trailer[:Prev].to_i
                    end

                    # Prepend the revision.
                    revisions.unshift(revision)
                end

                pdf.revisions.clear
                revisions.each do |rev|
                    pdf.revisions.push(rev)
                    pdf.insert(rev.xrefstm) if rev.has_xrefstm?
                end

                parse_finalize(pdf)

                pdf
            end

            private

            def parse_revision(pdf, offset)
                raise ParsingError, "Invalid xref offset" if offset < 0 or offset >= @data.string.size

                @data.pos = offset

                # Create a new revision.
                revision = PDF::Revision.new(pdf)

                # Regular xref section.
                if @data.match?(/#{XRef::Section::TOKEN}/)
                    xreftable = parse_xreftable
                    raise ParsingError, "Cannot parse xref section" if xreftable.nil?

                    revision.xreftable = xreftable
                    revision.trailer = parse_trailer

                    # Handle hybrid cross-references.
                    if revision.trailer[:XRefStm].is_a?(Integer)
                        begin
                            offset = revision.trailer[:XRefStm].to_i
                            xrefstm = parse_object(offset)

                            if xrefstm.is_a?(XRefStream)
                                revision.xrefstm = xrefstm
                            else
                                warn "Invalid xref stream at offset #{offset}"
                            end

                        rescue
                            warn "Cannot parse xref stream at offset #{offset}"
                        end
                    end

                # The xrefs are stored in a stream.
                else
                    xrefstm = parse_object
                    raise ParsingError, "Invalid xref stream" unless xrefstm.is_a?(XRefStream)

                    revision.xrefstm = xrefstm

                    # Search for the trailer.
                    if @data.skip_until Regexp.union(Trailer::XREF_TOKEN, *Trailer::TOKENS)
                        @data.pos -= @data.matched_size

                        revision.trailer = parse_trailer
                    else
                        warn "No trailer found."
                        revision.trailer = Trailer.new
                    end
                end

                revision
            end
        end
    end

end
