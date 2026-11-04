list(APPEND PATCH_FILES trim_the_fat.patch)

list(APPEND CFG_CMD COMMAND env)
append_autotools_vars(CFG_CMD)
list(APPEND CFG_CMD
    ${SOURCE_DIR}/configure --host=${CHOST} --prefix=${STAGING_DIR}
    --disable-$<IF:$<BOOL:${MONOLIBTIC}>,shared,static>
    --enable-$<IF:$<BOOL:${MONOLIBTIC}>,static,shared>
    --enable-silent-rules
)

list(APPEND BUILD_CMD COMMAND make)

list(APPEND INSTALL_CMD COMMAND make install)

if(NOT MONOLIBTIC)
    set(LIB_SPEC unibreak VERSION 8)
    if(APPLE)
        append_shared_lib_fix_commands(INSTALL_CMD ${LIB_SPEC} ID)
    endif()
    append_shared_lib_install_commands(INSTALL_CMD ${LIB_SPEC})
endif()

external_project(
    DOWNLOAD URL 8114d560b34581e385d9da96b5c8bfd9
    https://github.com/adah1972/libunibreak/releases/download/libunibreak_8_0/libunibreak-8.0.tar.gz
    PATCH_FILES ${PATCH_FILES}
    CONFIGURE_COMMAND ${CFG_CMD}
    BUILD_COMMAND ${BUILD_CMD}
    INSTALL_COMMAND ${INSTALL_CMD}
)
