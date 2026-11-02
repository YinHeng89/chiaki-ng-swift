find_program(GIT_EXECUTABLE git REQUIRED)
execute_process(COMMAND "${GIT_EXECUTABLE}" apply --reverse --check "${PATCH_FILE}"
    WORKING_DIRECTORY "${SDL_SOURCE}" RESULT_VARIABLE already_applied OUTPUT_QUIET ERROR_QUIET)
if(NOT already_applied EQUAL 0)
    execute_process(COMMAND "${GIT_EXECUTABLE}" apply --check "${PATCH_FILE}"
        WORKING_DIRECTORY "${SDL_SOURCE}" COMMAND_ERROR_IS_FATAL ANY)
    execute_process(COMMAND "${GIT_EXECUTABLE}" apply "${PATCH_FILE}"
        WORKING_DIRECTORY "${SDL_SOURCE}" COMMAND_ERROR_IS_FATAL ANY)
endif()
