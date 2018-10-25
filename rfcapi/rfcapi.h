/*
 * If not stated otherwise in this file or this component's Licenses.txt file the
 * following copyright and licenses apply:
 *
 * Copyright 2016 RDK Management
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
*/

#ifndef RFCAPI_H_
#define RFCAPI_H_

#include <string.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C"
{
#endif
#include <wdmp-c.h>
#ifdef __cplusplus
}
#endif

#define MAX_PARAM_LEN     (2*1024)

typedef struct _RFC_Param_t {
   char name[MAX_PARAM_LEN];
   char value[MAX_PARAM_LEN];
   DATA_TYPE type;
} RFC_ParamData_t;

WDMP_STATUS getRFCParameter(char *pcCallerID, const char* pcParameterName, RFC_ParamData_t *pstParamData);
WDMP_STATUS setRFCParameter(char *pcCallerID, const char* pcParameterName, const char* pcParameterValue, DATA_TYPE eDataType);
const char* getRFCErrorString(WDMP_STATUS code);

#endif
