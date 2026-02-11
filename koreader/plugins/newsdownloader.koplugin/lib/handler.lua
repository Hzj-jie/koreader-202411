---
--  Overview:
--  =========
--      Standard XML event handler(s) for XML parser module (xml.lua)
--
--  Features:
--  =========
--      printHandler        - Generate XML event trace
--      domHandler          - Generate DOM-like node tree
--      simpleTreeHandler   - Generate 'simple' node tree
--
--  API:
--  ====
--      Must be called as handler function from xmlParser
--      and implement XML event callbacks (see xmlParser.lua
--      for callback API definition)
--
--      printHandler:
--      -------------
--
--      printHandler prints event trace for debugging
--
--      domHandler:
--      -----------
--
--      domHandler generates a DOM-like node tree  structure with
--      a single ROOT node parent - each node is a table comprising
--      fields below.
--
--      node = { _name = <Element Name>,
--              _type = ROOT|ELEMENT|TEXT|COMMENT|PI|DECL|DTD,
--              _attr = { Node attributes - see callback API },
--              _parent = <Parent Node>
--              _children = { List of child nodes - ROOT/NODE only }
--            }
--
--      The dom structure is capable of representing any valid XML document
--
--      simpleTreeHandler
--      -----------------
--
--      simpleTreeHandler is a simplified handler which attempts
--      to generate a more 'natural' table based structure which
--      supports many common XML formats.
--
--      The XML tree structure is mapped directly into a recursive
--      table structure with node names as keys and child elements
--      as either a table of values or directly as a string value
--      for text. Where there is only a single child element this
--      is inserted as a named key - if there are multiple
--      elements these are inserted as a vector (in some cases it
--      may be preferable to always insert elements as a vector
--      which can be specified on a per element basis in the
--      options).  Attributes are inserted as a child element with
--      a key of '_attr'.
--
--      Only Tag/Text & CDATA elements are processed - all others
--      are ignored.
--
--      This format has some limitations - primarily
--
--      * Mixed-Content behaves unpredictably - the relationship
--        between text elements and embedded tags is lost and
--        multiple levels of mixed content does not work
--      * If a leaf element has both a text element and attributes
--        then the text must be accessed through a vector (to
--        provide a container for the attribute)
--
--      In general however this format is relatively useful.
--
--      It is much easier to understand by running some test
--      data through 'textxml.lua -simpletree' than to read this)
--
--  Options
--  =======
--      simpleTreeHandler.options.noReduce = { <tag> = bool,.. }
--
--          - Nodes not to reduce children vector even if only
--            one child
--
--      domHandler.options.(comment|pi|dtd|decl)Node = bool
--
--          - Include/exclude given node types
--
--  Usage
--  =====
--      Parsed as delegate in xmlParser constructor and called
--      as callback by xmlParser:parse(xml) method.
--
--      See textxml.lua for examples
--  License:
--  ========
--
--      This code is freely distributable under the terms of the Lua license
--      (<a href="http://www.lua.org/copyright.html">http://www.lua.org/copyright.html</a>)
--
--  History
--  =======
--  $Id: handler.lua,v 1.1.1.1 2001/11/28 06:11:33 paulc Exp $
--
--  $Log: handler.lua,v $
--  Revision 1.1.1.1  2001/11/28 06:11:33  paulc
--  Initial Import
--@author Paul Chakravarti (paulc@passtheaardvark.com)<p/>

--Obtém a primeira chave de uma tabela
--@param Tabela de onde deverá ser obtido o primeiro elemento
--@return Retorna a primeira chave da tabela
local function getFirstKey(tb)
  if type(tb) == "table" then
    --O uso da função next não funciona para pegar o primeiro elemento. Trava aqui
    -- This comment seems weird, but just keep it as-is.
    --k, v = next(tb)
    --return k
    -- TODO: Address this luacheck warning.
    for k, __ in pairs(tb) do -- luacheck: ignore 512
      return k
    end
    return nil
  else
    return tb
  end
end

---Handler to generate a lua table from a XML content string
local function simpleTreeHandler()
  local obj = {}

  obj.root = {}
  obj.stack = { obj.root, n = 1 }
  obj.options = { noreduce = {} }

  obj.reduce = function(self, node, key, parent)
    -- Recursively remove redundant vectors for nodes
    -- with single child elements
    for k, v in pairs(node) do
      if type(v) == "table" then
        self:reduce(v, k, node)
      end
    end
    if #node == 1 and not self.options.noreduce[key] and node._attr == nil then
      parent[key] = node[1]
    else
      node.n = nil
    end
  end

  --@param t Table that represents a XML tag
  --@param a Attributes table (_attr)
  obj.starttag = function(self, t, a)
    local node = {}
    if self.parseAttributes == true then
      node._attr = a
    end

    local current = self.stack[#self.stack]
    if current[t] then
      table.insert(current[t], node)
    else
      current[t] = { node, n = 1 }
    end
    table.insert(self.stack, node)
  end

  --@param t Tag name
  obj.endtag = function(self, t, s)
    --Tabela que representa a tag atualmente sendo processada
    local current = self.stack[#self.stack]
    --Tabela que representa a tag na qual a tag
    --atual está contida.
    local prev = self.stack[#self.stack - 1]
    if not prev[t] then
      error("XML Error - Unmatched Tag [" .. s .. ":" .. t .. "]\n")
    end
    if prev == self.root then
      -- Once parsing complete recursively reduce tree
      self:reduce(prev, nil, nil)
    end

    local firstKey = getFirstKey(current)
    --Se a primeira chave da tabela que representa
    --a tag  atual não possui nenhum elemento,
    --é porque não há nenhum valor associado à tag
    -- (como nos casos de tags automaticamente fechadas como <senha />).
    --Assim, atribui uma string vazia a mesma para
    --que seja retornado vazio no lugar da tag e não
    --uma tabela. Retornando uma string vazia
    --simplifica para as aplicações NCLua
    --para imprimir tal valor.
    if firstKey == nil then
      current[t] = ""
      prev[t] = ""
    end

    table.remove(self.stack)
  end

  obj.text = function(self, t)
    local current = self.stack[#self.stack]
    table.insert(current, t)
  end

  obj.cdata = obj.text

  return obj
end

return { simpleTreeHandler = simpleTreeHandler }
