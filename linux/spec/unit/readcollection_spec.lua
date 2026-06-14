describe("ReadCollection module", function()
    local ReadCollection
    local FFIUtil, lfs
    local orig_realpath, orig_attributes
    local collection_file

    setup(function()
        require("commonrequire")
        local DataStorage = require("datastorage")
        collection_file = DataStorage:getSettingsDir() .. "/collection.lua"

        FFIUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")

        orig_realpath = FFIUtil.realpath
        orig_attributes = lfs.attributes

        -- Mock FFIUtil.realpath to support mock files
        FFIUtil.realpath = function(path)
            local path_str = tostring(path)
            local found = string.find(path_str, "mock", 1, true)
            if found then
                return "/mock/path/" .. path_str
            end
            return orig_realpath(path)
        end

        -- Mock lfs.attributes to support mock files and mock modification time
        lfs.attributes = function(path, request)
            local path_str = tostring(path)
            local found = string.find(path_str, "mock", 1, true)
            if found then
                if request == "modification" then
                    return 123456
                end
                return { mode = "file", size = 100 }
            end
            return orig_attributes(path, request)
        end
    end)

    teardown(function()
        FFIUtil.realpath = orig_realpath
        lfs.attributes = orig_attributes
    end)

    before_each(function()
        -- Clean up collection file before each test to ensure isolation
        os.remove(collection_file)
        package.loaded["readcollection"] = nil -- force reload to re-initialize
        ReadCollection = require("readcollection")
    end)

    after_each(function()
        os.remove(collection_file)
    end)

    it("should initialize with default favorites collection", function()
        assert.truthy(ReadCollection.coll)
        assert.truthy(ReadCollection.coll["favorites"])
        assert.are.same({}, ReadCollection.coll["favorites"])
    end)

    describe("Collection Management", function()
        it("should add a new collection", function()
            ReadCollection:addCollection("my_books")
            assert.truthy(ReadCollection.coll["my_books"])
            assert.are.same({}, ReadCollection.coll["my_books"])
            assert.truthy(ReadCollection.coll_order["my_books"])
        end)

        it("should rename a collection", function()
            ReadCollection:addCollection("my_books")
            ReadCollection:renameCollection("my_books", "read_later")
            assert.falsy(ReadCollection.coll["my_books"])
            assert.truthy(ReadCollection.coll["read_later"])
            assert.are.same({}, ReadCollection.coll["read_later"])
        end)

        it("should remove a collection", function()
            ReadCollection:addCollection("my_books")
            ReadCollection:removeCollection("my_books")
            assert.falsy(ReadCollection.coll["my_books"])
            assert.falsy(ReadCollection.coll_order["my_books"])
        end)
    end)

    describe("Item Management", function()
        before_each(function()
            ReadCollection:addCollection("my_books")
        end)

        it("should add an item to a collection", function()
            local mock_file = "mock-file-1.epub"
            ReadCollection:addItem(mock_file, "my_books")

            local expected_path = "/mock/path/" .. mock_file
            assert.is_true(ReadCollection:isFileInCollection(mock_file, "my_books"))
            assert.is_true(ReadCollection:isFileInCollections(mock_file))

            local collections = ReadCollection:getCollectionsWithFile(mock_file)
            assert.truthy(collections["my_books"])

            local item = ReadCollection.coll["my_books"][expected_path]
            assert.truthy(item)
            assert.are.equal(expected_path, item.file)
            assert.are.equal("mock-file-1.epub", item.text)
            assert.are.equal(1, item.order)
        end)

        it("should remove an item from a collection", function()
            local mock_file = "mock-file-1.epub"
            ReadCollection:addItem(mock_file, "my_books")
            assert.is_true(ReadCollection:isFileInCollection(mock_file, "my_books"))

            ReadCollection:removeItem(mock_file, "my_books")
            assert.is_false(ReadCollection:isFileInCollection(mock_file, "my_books"))
        end)

        it("should update item path when renamed", function()
            local mock_file = "mock-file-1.epub"
            ReadCollection:addItem(mock_file, "my_books")

            local new_mock_file = "mock-file-1-renamed.epub"
            ReadCollection:updateItem(mock_file, new_mock_file)

            assert.is_false(ReadCollection:isFileInCollection(mock_file, "my_books"))
            assert.is_true(ReadCollection:isFileInCollection(new_mock_file, "my_books"))
        end)
    end)

    describe("Ordering", function()
        it("should return ordered collection", function()
            ReadCollection:addCollection("ordered_coll")
            ReadCollection:addItem("mock-file-b.epub", "ordered_coll") -- order 1
            ReadCollection:addItem("mock-file-a.epub", "ordered_coll") -- order 2

            local ordered = ReadCollection:getOrderedCollection("ordered_coll")
            assert.are.equal(2, #ordered)
            assert.are.equal("/mock/path/mock-file-b.epub", ordered[1].file)
            assert.are.equal("/mock/path/mock-file-a.epub", ordered[2].file)

            -- Update order manually (swap them in the array)
            local temp = ordered[1]
            ordered[1] = ordered[2]
            ordered[2] = temp

            ReadCollection:updateCollectionOrder("ordered_coll", ordered)

            local new_ordered = ReadCollection:getOrderedCollection("ordered_coll")
            assert.are.equal("/mock/path/mock-file-a.epub", new_ordered[1].file)
            assert.are.equal("/mock/path/mock-file-b.epub", new_ordered[2].file)
        end)
    end)
end)
