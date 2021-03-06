
-------------------------------------------------------------
-- class Sheet
local Sheet = {}


function Sheet.new(ptr, excel)	
	local o = {sheet = ptr, owner = excel}
	setmetatable(o, Sheet)
	Sheet.__index = Sheet
	return o
end

--AA相当于10进制27
function Sheet:getColumnNumber( s )
	local number_tbl = {}
	for k,_ in string.gmatch(s, '%u') do 
		local n = string.byte(k) - string.byte('A') + 1
		assert(n <= 26 and n > 0)
		table.insert(number_tbl, n) 
	end
	number_tbl = table.orderByDesc(number_tbl)
	return math.numberTable2X(number_tbl, 26)
end

function Sheet:getColumnString( num )
	--由于这个26进制比较奇怪,如果以时间举例就是0点不叫0点而叫24点
	--所以在计算进制前先-1，好了以后个位补1
	local number_tbl = math.dec2X(num - 1, 26)
	number_tbl[1] = number_tbl[1] + 1

	for i,v in ipairs(number_tbl) do		
		number_tbl[i] = string.char(string.byte('A') + v -1 )
	end
	--倒序一下
	number_tbl = table.orderByDesc(number_tbl)
	--字符串拼接一下
	local s = ''
	for _,v in ipairs(number_tbl) do
		s = s .. v
	end
	return s
end

--测试
assert(Sheet.getColumnNumber(nil, 'A') == 1)
assert(Sheet.getColumnNumber(nil, 'Z') == 26)
assert(Sheet.getColumnNumber(nil, 'AA') == 27)
assert(Sheet.getColumnNumber(nil, 'IV') == 256)
assert(Sheet.getColumnString(nil, 1) == 'A')
assert(Sheet.getColumnString(nil, 27) == 'AA')
assert(Sheet.getColumnString(nil, 256) == 'IV')
assert(Sheet.getColumnString(nil, 26) == 'Z')

function Sheet:getRangeString( startRange, width, height )
	assert(type(startRange) == 'string')
	--获得起点行号，及起点的列编号
	local startRow = string.gsub(startRange, '%u+', '')
	local startColumn = string.gsub(startRange, '%d+', '')
	--列编号相当于26进制的数字，我们把他转成10进制整数便于运算
	startRow = tonumber(startRow)
	startColumn = self:getColumnNumber(startColumn)
	local endRow, endColumn = assert(startRow) + height, startColumn + width
	--转成字母形式
	endColumn = self:getColumnString(endColumn)

	return startRange..':'..endColumn..endRow
end

--@startRange 起点格子编号：如AB189, AB列-189行
--@width 宽度几格
--@height 高度
function Sheet:getRange(startRange, width, height)	
	startRange = startRange or 'A1'
	width = width or self.sheet.Usedrange.columns.count
	height = height or self.sheet.Usedrange.Rows.count
	--如果格子选太多会导致crash,所以这里必须分页
	--TODO:这种方式性能还是不行，应该可以借助剪贴板,然后分割文本的方式提高性能

	--获得起点行号，及起点的列编号
	local startRow = string.gsub(startRange, '%u+', '')
	local startColumn = string.gsub(startRange, '%d+', '')
	
	my_assert(tonumber(startRow), string.format("%s %s %s",startRange, startRow, startColumn))
	--my_assert(tonumber(startColumn), startColumn)
	
	--把所有的数据组织成一张大表
	local data = {}

	--分页的大小
	local kStep = 200
	local ranges = {}
	for i=0,height,kStep do
		local cellStr = startColumn..(tonumber(startRow) + #ranges*kStep)
		local row_count = (i+kStep > height) and (height-i) or kStep
		if row_count > 0 then
			local range = self.sheet:Range(self:getRangeString(cellStr, width, row_count))
--			range:Copy()
			table.insert(ranges, {row_count, range})
			for j=1,row_count do
				local row = {}
				for k=1,width do
					row[k] = range.Value2[j][k]
				end
				table.insert(data, row)
			end
		end
	end	

	return data
end

function Sheet:pasteTable( activate_cell,str_data )
	--写到剪粘板,然后粘贴即可
	local content = table.concat(str_data, '\r\n')
	winapi.set_clipboard(content)

	--如果没有这一句,那么换一个工作表就会失败
	self.sheet:Activate()
	--local range = self.sheet:Range(activate_cell)
	--local cell = range:Offset(0, 0)
	--cell:Select()
	self.sheet:Range(activate_cell):Activate()
	self.sheet:Paste()
	--保存一下防止失败
	--self.owner:save()
end

--传入一个table设置到相应的格子上面
--@dstRange 目标单元格
--@data 所有数据的集合
--@row_count 需要修改的行数量,用于计算偏移
--@column_count 列数
function Sheet:setRange( dstRange, data, row_count, column_count )
	dstRange = dstRange or 'A1'	

	--获得起点行号，及起点的列编号
	local startRow = string.gsub(dstRange, '%u+', '')
	local startColumn = string.gsub(dstRange, '%d+', '')
	--设置值,注意空的情况
	local stringbuilder = {}
	for i=1, row_count do
		-- local row = data[i]
		-- for j=1, column_count do			
	 --    	self.sheet.Cells(startRow + i -1, self:getColumnNumber(startColumn) + j -1).Value2 = row[j]
	 --  	end
	  	table.insert(stringbuilder, table.concat(data[i], '\t'))
	  	--本来要做分页的，其实没有必要,那不然就分10000吧
	  	if #stringbuilder >= 10000 or (i == row_count) then	  		
	  		local rowIndex = startRow + i - #stringbuilder
	  		local activate_cell = startColumn .. rowIndex
			self:pasteTable( activate_cell, stringbuilder)
			stringbuilder = {}
	  	end
	end
end

--取得某列的所有集合
function Sheet:getColumn(startRange, endRow)
	--要么是个nil要么是个数字
	assert(not endRow or type(endRow) == 'number', endRow)
	startRow = startRow or 1
	endRow = endRow or  (self.sheet.Usedrange.Rows.count - startRow)
	
	--TODO:性能优化
	local range = self:getRange(startRange, 1, endRow)
	local data = {}
	for i=1, #range do
		local v = range[i][1]
		data[i] = v and v or ''
	end
	return data
end

--从指定的位置开始设置值
function Sheet:setColumn(startRange, data)
	--获得起点行号，及起点的列编号
	return self:pasteTable(startRange, data)

	--以下是以单元格的方式操作性能较差
	--local startRow = string.gsub(startRange, '%u+', '')
	--local startColumn = string.gsub(startRange, '%d+', '')
	--for i=1,#data do
	--	self.sheet.Cells(tonumber(startRow) + i -1, self:getColumnNumber(startColumn)).Value2 = data[i]
	--end
end

function Sheet:getCell( startRange, column, row )
	--获得起点行号，及起点的列编号
	local startRow = tonumber(string.gsub(dstRange, '%u+', ''))
	local startColumn = string.gsub(dstRange, '%d+', '')
	return self.sheet.Cells(startRow + row -1, self:getColumnNumber(startColumn) + column -1).Value2
end

--根据起始格子及偏移列数及行数设置值
function Sheet:setCell(startRange, column, row, value)
	--获得起点行号，及起点的列编号
	local startRow = tonumber(string.gsub(dstRange, '%u+', ''))
	local startColumn = string.gsub(dstRange, '%d+', '')
	self.sheet.Cells(startRow + row -1, self:getColumnNumber(startColumn) + column -1).Value2 = value
end

function Sheet:getUseRange()
	return self.sheet.Usedrange.Rows.count,
		self.sheet.Usedrange.columns.count
end

return Sheet
