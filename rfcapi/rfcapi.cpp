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

#include "rfcapi.h"
#include <curl/curl.h>
#include "cJSON.h"
#include <sstream>
#include "rdk_debug.h"
using namespace std;

#define LOG_RFCAPI  "LOG.RDK.RFCAPI"
static const char *url = "http://127.0.0.1:11999";

static size_t writeCurlResponse(void *ptr, size_t size, size_t nmemb, string stream)
{
   size_t realsize = size * nmemb;
   string temp(static_cast<const char*>(ptr), realsize);
   stream.append(temp);
   return realsize;
}

WDMP_STATUS getRFCParameter(char *pcCallerID, const char* pcParameterName, RFC_ParamData_t *pstParam)
{
   WDMP_STATUS ret = WDMP_FAILURE;
   long http_code = 0;
   string response;
   CURL *curl_handle = NULL;
   CURLcode res = CURLE_OK;
   curl_handle = curl_easy_init();
   string data = "\{\"names\" : [\"";
   data.append(pcParameterName);
   data.append("\"]}");
   RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"getRFCParam data = %s, datalen = %d\n", data.c_str(), data.length());
   if (curl_handle) 
   {
      curl_easy_setopt(curl_handle, CURLOPT_URL, url);
      curl_easy_setopt(curl_handle, CURLOPT_CUSTOMREQUEST, "GET");
      curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDSIZE, (long) data.length());
      curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDS, data.c_str());
      curl_easy_setopt(curl_handle, CURLOPT_FOLLOWLOCATION, 1);
      curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, writeCurlResponse);
      curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, &response);

      res = curl_easy_perform(curl_handle);
      curl_easy_getinfo(curl_handle, CURLINFO_RESPONSE_CODE, &http_code);
      RDK_LOG(RDK_LOG_INFO, LOG_RFCAPI,"curl response : %d http response code: %ld\n", res, http_code);
      curl_easy_cleanup(curl_handle);
   }
   else
   {
      RDK_LOG(RDK_LOG_ERROR, LOG_RFCAPI,"Could not perform curl \n");
   }
   if (res == CURLE_OK)
   {
      cJSON *response_json = NULL;
      RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"Curl response: %s\n", response.c_str());
      response_json = cJSON_Parse(response.c_str());

      if (response_json)
      {
         cJSON *items = cJSON_GetObjectItem(response_json, "parameters");

         for (int i = 0 ; i < cJSON_GetArraySize(items) ; i++)
         {
            cJSON* subitem  = cJSON_GetArrayItem(items, i);
            cJSON* name    = cJSON_GetObjectItem(subitem, "name");
            if(name)
            {
               strncpy(pstParam->name, name->valuestring,strlen(name->valuestring));
               pstParam->name[strlen(name->valuestring)] = '\0';
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"name = %s\n", pstParam->name);
            }

            cJSON* dataType = cJSON_GetObjectItem(subitem, "dataType");
            if (dataType)
            {
               pstParam->type = (DATA_TYPE)dataType->valueint;
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"type = %s\n", pstParam->type);
            }
            cJSON* value = cJSON_GetObjectItem(subitem, "value");
            if (value)
            {
               strncpy(pstParam->value, value->valuestring,strlen(value->valuestring));
               pstParam->value[strlen(value->valuestring)] = '\0';
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"value = %s\n", pstParam->value);
            }
            cJSON* message = cJSON_GetObjectItem(subitem, "message");
            if (message)
            {
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"message = %s\n", message->valuestring);
            }
         }
         cJSON* statusCode = cJSON_GetObjectItem(response_json, "statusCode");
         if(statusCode)
         {
            ret = (WDMP_STATUS)statusCode->valueint;
            RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"statusCode = %d\n", ret);
         }
      }
   }
   return ret;
}

WDMP_STATUS setRFCParameter(char *pcCallerID, const char* pcParameterName, const char* pcParameterValue, DATA_TYPE eDataType)
{
   WDMP_STATUS ret = WDMP_FAILURE;
   long http_code = 0;
   string response;
   CURL *curl_handle = NULL;
   CURLcode res = CURLE_OK;
   curl_handle = curl_easy_init();

   ostringstream ss;
   ss << eDataType;
   string strDataType = ss.str();

   string data = "\{\"parameters\" : [{\"name\":\"";
   data.append(pcParameterName);
   data.append("\",\"value\":\"");
   data.append(pcParameterValue);
   data.append("\",\"dataType\":");
   data.append(strDataType);
   data.append("}]}");
   RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"setRFCParam data = %s, datalen = %d\n", data.c_str(), data.length());

   if (curl_handle)
   {
      curl_easy_setopt(curl_handle, CURLOPT_URL, url);
      curl_easy_setopt(curl_handle, CURLOPT_HTTPPOST, 1L);
      curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDSIZE, (long) data.length());
      curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDS, data.c_str());
      curl_easy_setopt(curl_handle, CURLOPT_FOLLOWLOCATION, 1);
      curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, writeCurlResponse);
      curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, &response);

      res = curl_easy_perform(curl_handle);
      curl_easy_getinfo(curl_handle, CURLINFO_RESPONSE_CODE, &http_code);

      RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"curl response : %d http response code: %ld\n", res, http_code);
      curl_easy_cleanup(curl_handle);
   }
   else
   {
      RDK_LOG(RDK_LOG_ERROR, LOG_RFCAPI,"Could not perform curl \n");
   }
   if (res == CURLE_OK)
   {
      cJSON *response_json = NULL;
      RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"Curl response: %s\n", response.c_str());
      response_json = cJSON_Parse(response.c_str());
      if (response_json)
      {
         cJSON* statusCode = cJSON_GetObjectItem(response_json, "statusCode");
         if(statusCode)
         {
            ret = (WDMP_STATUS)statusCode->valueint;
            RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"statusCode = %d\n", ret);
         }
      }
   }
   return ret;
}

/**
* Return the textual description of error code from wdmp_status
*@param [in] wdmp_status
*@param [out] textual description of error code.
*/
const char * getRFCErrorString(WDMP_STATUS code)
{
   const char * err_string;
   switch(code)
   {
      case WDMP_FAILURE:
         err_string = " Request Failed";
            break;
      case WDMP_ERR_TIMEOUT:
         err_string = " Request Timeout";
            break;
       case WDMP_ERR_INVALID_PARAMETER_NAME:
          err_string = " Invalid Parameter Name";
             break;
       case WDMP_ERR_INVALID_PARAMETER_TYPE:
          err_string = " Invalid Parameter Type";
             break;
       case WDMP_ERR_INVALID_PARAMETER_VALUE:
          err_string = " Invalid Parameter Value";
             break;
       case WDMP_ERR_NOT_WRITABLE:
          err_string = " Not writable";
             break;
       case WDMP_ERR_SETATTRIBUTE_REJECTED:
          err_string = " SetAttribute Rejected";
             break;
       case WDMP_ERR_NAMESPACE_OVERLAP:
          err_string = " Namespace Overlap";
             break;
       case WDMP_ERR_UNKNOWN_COMPONENT:
          err_string = " Unknown Component";
             break;
       case WDMP_ERR_NAMESPACE_MISMATCH:
          err_string = " Namespace Mismatch";
             break;
       case WDMP_ERR_UNSUPPORTED_NAMESPACE:
          err_string = " Unsupported Namespace";
             break;
       case WDMP_ERR_DP_COMPONENT_VERSION_MISMATCH:
          err_string = " Component Version Mismatch";
             break;
       case WDMP_ERR_INVALID_PARAM:
          err_string = " Invalid Param";
             break;
       case WDMP_ERR_UNSUPPORTED_DATATYPE:
          err_string = " Unsupported Datatype";
             break;
       case WDMP_STATUS_RESOURCES:
          err_string = " Resources";
             break;
       case WDMP_ERR_WIFI_BUSY:
          err_string = " Wifi Busy";
             break;
       case WDMP_ERR_INVALID_ATTRIBUTES:
          err_string = " Invalid Attributes";
             break;
       case WDMP_ERR_WILDCARD_NOT_SUPPORTED:
          err_string = " Wildcard Not Supported";
             break;
       case WDMP_ERR_SET_OF_CMC_OR_CID_NOT_SUPPORTED:
          err_string = " Set of CMC or CID Not Supported";
             break;
       case WDMP_ERR_VALUE_IS_EMPTY:
          err_string = " Value is Empty";
             break;
       case WDMP_ERR_VALUE_IS_NULL:
          err_string = " Value is Null";
             break;
       case WDMP_ERR_DATATYPE_IS_NULL:
          err_string = " Datatype is Null";
             break;
       case WDMP_ERR_CMC_TEST_FAILED:
          err_string = " CMC Test Failed";
             break;
       case WDMP_ERR_NEW_CID_IS_MISSING:
          err_string = " New CID is Missing";
             break;
       case WDMP_ERR_CID_TEST_FAILED:
          err_string = " CID Test Failed";
             break;
       case WDMP_ERR_SETTING_CMC_OR_CID:
          err_string = " Setting CMC or CID";
             break;
       case WDMP_ERR_INVALID_INPUT_PARAMETER:
          err_string = " Invalid Input Parameter";
             break;
       case WDMP_ERR_ATTRIBUTES_IS_NULL:
          err_string = " Attributes is Null";
             break;
       case WDMP_ERR_NOTIFY_IS_NULL:
          err_string = " Notify is Null";
             break;
       case WDMP_ERR_INVALID_WIFI_INDEX:
          err_string = " Invalid Wifi Index";
             break;
       case WDMP_ERR_INVALID_RADIO_INDEX:
          err_string = " Invalid Radio Index";
             break;
       case WDMP_ERR_ATOMIC_GET_SET_FAILED:
          err_string = " Atomic Get Set Failed";
             break;
       case WDMP_ERR_METHOD_NOT_SUPPORTED:
          err_string = " Method Not Supported";
             break;
       case WDMP_ERR_INTERNAL_ERROR:
          err_string = " Internal Error";
             break;
       case WDMP_ERR_DEFAULT_VALUE:
          err_string = " Default Value";
             break;
       default:
          err_string = " Unknown error code";
   }
   return err_string;
}
