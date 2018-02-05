##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2018 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################
#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.
AC_PREREQ([2.68])
AC_INIT([rfctools], [1.0], [josekutty@tataelxsi.co.in])
AC_CONFIG_SRCDIR([utils/jsonhandler.cpp])
AC_CONFIG_SRCDIR([utils/trsetutils.cpp])
AC_CONFIG_HEADERS([utils/config.h])

AM_INIT_AUTOMAKE([foreign])
LT_INIT
LT_LANG([C++])
AC_PROG_CXX
AC_PROG_CC

# Checks for libraries.
AC_CHECK_LIB([IARMBus], [IARM_Bus_Init])
AC_CHECK_LIB([cjson], [cJSON_Parse])

# Checks for header files.
AC_CHECK_HEADERS([stdlib.h string.h unistd.h])

AC_CONFIG_FILES([
        Makefile
	utils/Makefile])
AC_OUTPUT

