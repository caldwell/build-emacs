#!/usr/bin/env ruby
#  Copyright © 2016-2017 David Caldwell
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Downloads brew formula source code (including dependencies).
# Usage: brew source <formula>... <destdir>

require 'fileutils'

dest = ARGV.pop

def fetch_source_and_deps(formula, dest)
  cache = formula.fetch
  FileUtils.cp(cache, dest)
  formula.deps.each {|dep| fetch_source_and_deps(dep.to_formula, dest) if dep.required? }
end

ARGV.each do |package|
  formula = Formulary.find_with_priority(package)
  fetch_source_and_deps(formula, dest)
end
