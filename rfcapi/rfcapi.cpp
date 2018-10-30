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

#include <fstream>
#include <sstream>
#include <curl/curl.h>
#include <string>

#include "rfcapi.h"
#include "cJSON.h"
#include "rdk_debug.h"
#include "rfccache.h"
using namespace std;

#define TR181_RFC_PREFIX   "Device.DeviceInfo.X_RDKCENTRAL-COM_RFC"
static const char *url = "http://127.0.0.1:11999";
static bool tr69hostif_http_server_ready = false;

#ifdef TEMP_LOGGING
static ofstream logofs;

static void openLogFile()
{
   if (!logofs.is_open())
      logofs.open("/opt/logs/rfcscript.log", ios_base::app); 
}

static string prefix()
{
    time_t timer;
    char buffer[50];
    struct tm* tm_info;
    time(&timer);
    tm_info = localtime(&timer);
    strftime(buffer, 50, "rfcapi:%Y-%m-%d %H:%M:%S ", tm_info);
    return string(buffer);
}
#endif

static size_t writeCurlResponse(void *ptr, size_t size, size_t nmemb, string stream)
{
   size_t realsize = size * nmemb;
   string temp(static_cast<const char*>(ptr), realsize);
   stream.append(temp);
   return realsize;
}

WDMP_STATUS getRFCParameter(char *pcCallerID, const char* pcParameterName, RFC_ParamData_t *pstParam)
{
#ifdef TEMP_LOGGING
   openLogFile();
#endif
   WDMP_STATUS ret = WDMP_FAILURE;
   long http_code = 0;
   string response;
   CURL *curl_handle = NULL;
   CURLcode res = CURLE_FAILED_INIT;

   if(!strcmp(pcParameterName+strlen(pcParameterName)-1,"."))
   {
#ifdef TEMP_LOGGING
       logofs << prefix() << __FUNCTION__ << ": RFC API doesn't support wildcard parameterName " << endl;
#endif
       RDK_LOG (RDK_LOG_DEBUG, LOG_RFCAPI, "%s: RFC API doesn't support wildcard parameterName\n", __FUNCTION__);
       return ret;
   }

   if(!tr69hostif_http_server_ready)
   {
      ifstream ifs_rfc("/tmp/.tr69hostif_http_server_ready");
      if(!ifs_rfc.is_open())
      {
#ifdef TEMP_LOGGING
         logofs << prefix() << __FUNCTION__ << ": file /tmp/.tr69hostif_http_server_ready doesn't exist, http server isn't ready yet" << endl;
#endif
         RDK_LOG (RDK_LOG_ERROR, LOG_RFCAPI, "%s: file /tmp/.tr69hostif_http_server_ready doesn't exist, http server isn't ready yet\n", __FUNCTION__);

         if(strncmp(pcParameterName, "RFC_", 4) == 0 && strchr(pcParameterName, '.') == NULL)
         {
            RFCCache rfcVarCache;
            bool initDone = rfcVarCache.initCache(RFC_VAR);
#ifdef TEMP_LOGGING
            logofs << prefix() << __FUNCTION__ << ": RFCVarCache initDone = " << initDone << endl;
#endif
            if (initDone)
            {
               string retValue = rfcVarCache.getValue(pcParameterName);
#ifdef TEMP_LOGGING
               logofs << prefix() << __FUNCTION__ << ": Value for " << pcParameterName << "retrieved from RFCStoreCache = " << retValue << endl;
#endif
               if(retValue.length() > 0)
               {
                  strncpy(pstParam->name, pcParameterName, strlen(pcParameterName));
                  pstParam->name[strlen(pcParameterName)] = '\0';

                  pstParam->type = WDMP_STRING; //default to string for RFC Variables as they don't follow data-model.xml

                  strncpy(pstParam->value, retValue.c_str(), strlen(retValue.c_str()));
                  pstParam->value[strlen(retValue.c_str())] = '\0';

                  return WDMP_SUCCESS;
               }
            }
         }
         else if (strstr(pcParameterName, TR181_RFC_PREFIX) != NULL)
         {
            RFCCache rfcStoreCache;
            bool initDone = rfcStoreCache.initCache(RFC_TR181_STORE);
#ifdef TEMP_LOGGING
            logofs << prefix() << __FUNCTION__ << ": RFCStoreCache initDone = " << initDone << endl;
#endif
            if (initDone)
            {
               string retValue = rfcStoreCache.getValue(pcParameterName);
#ifdef TEMP_LOGGING
               logofs << prefix() << __FUNCTION__ << ": Value for " << pcParameterName << "retrieved from RFCStoreCache = " << retValue << endl;
#endif
               if(retValue.length() > 0)
               {
                  strncpy(pstParam->name, pcParameterName, strlen(pcParameterName));
                  pstParam->name[strlen(pcParameterName)] = '\0';

                  pstParam->type = WDMP_NONE; //The caller must know what type they are expecting if they are requesting a param before the hostif is ready.

                  strncpy(pstParam->value, retValue.c_str(), strlen(retValue.c_str()));
                  pstParam->value[strlen(retValue.c_str())] = '\0';

                  return WDMP_SUCCESS;
               }
            }
            return WDMP_FAILURE;
         }
         else
         {
#ifdef TEMP_LOGGING
            logofs << prefix() << __FUNCTION__ << ": Param " << pcParameterName << ": is not available before http server is ready " << endl;
#endif
         }
      }
      else
      {
         ifs_rfc.close();
#ifdef TEMP_LOGGING
         logofs << prefix() << __FUNCTION__ << ": http server is ready" << endl;
#endif
         RDK_LOG (RDK_LOG_DEBUG, LOG_RFCAPI, "%s: http server is ready\n", __FUNCTION__);
         tr69hostif_http_server_ready = true;
      }
   }

   curl_handle = curl_easy_init();
   string data = "\{\"names\" : [\"";
   data.append(pcParameterName);
   data.append("\"]}");
#ifdef TEMP_LOGGING
   logofs << prefix() << "getRFCParam data = " << data << " dataLen = " << data.length() << endl;
#endif
   RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"getRFCParam data = %s, datalen = %d\n", data.c_str(), data.length());
   if (curl_handle) 
   {
       char pcCallerIDHeader[128];
       if(pcCallerID)
           sprintf(pcCallerIDHeader, "CallerID: %s", pcCallerID);
       else
           sprintf(pcCallerIDHeader, "CallerID: Unknown");
       struct curl_slist *customHeadersList = NULL;
       customHeadersList = curl_slist_append(customHeadersList, pcCallerIDHeader);
       curl_easy_setopt(curl_handle, CURLOPT_HTTPHEADER, customHeadersList);

       curl_easy_setopt(curl_handle, CURLOPT_URL, url);
       curl_easy_setopt(curl_handle, CURLOPT_CUSTOMREQUEST, "GET");
       curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDSIZE, (long) data.length());
       curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDS, data.c_str());
       curl_easy_setopt(curl_handle, CURLOPT_FOLLOWLOCATION, 1);
       curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, writeCurlResponse);
       curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, &response);

       res = curl_easy_perform(curl_handle);
       curl_easy_getinfo(curl_handle, CURLINFO_RESPONSE_CODE, &http_code);
#ifdef TEMP_LOGGING
       logofs  << prefix() << "curl response = " << res << "http response code = " << http_code << endl;
#endif
       RDK_LOG(RDK_LOG_INFO, LOG_RFCAPI,"curl response : %d http response code: %ld\n", res, http_code);
       curl_easy_cleanup(curl_handle);

       curl_slist_free_all(customHeadersList);
   }
   else
   {
#ifdef TEMP_LOGGING
      logofs << prefix() << "Could not perform curl" << endl;
#endif
      RDK_LOG(RDK_LOG_ERROR, LOG_RFCAPI,"Could not perform curl \n");
   }
   if (res == CURLE_OK)
   {
      cJSON *response_json = NULL;
#ifdef TEMP_LOGGING
      logofs << prefix() << "curl response: " << response << endl;
#endif
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
#ifdef TEMP_LOGGING
               logofs << prefix() << "name = " << pstParam->name << endl;
#endif
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"name = %s\n", pstParam->name);
            }

            cJSON* dataType = cJSON_GetObjectItem(subitem, "dataType");
            if (dataType)
            {
               pstParam->type = (DATA_TYPE)dataType->valueint;
#ifdef TEMP_LOGGING
               logofs << prefix() << "dataType = " << pstParam->type << endl;
#endif
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"type = %d\n", pstParam->type);
            }
            cJSON* value = cJSON_GetObjectItem(subitem, "value");
            if (value)
            {
               strncpy(pstParam->value, value->valuestring,strlen(value->valuestring));
               pstParam->value[strlen(value->valuestring)] = '\0';
#ifdef TEMP_LOGGING
               logofs << prefix() << "value = " << pstParam->value << endl;
#endif
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"value = %s\n", pstParam->value);
            }
            cJSON* message = cJSON_GetObjectItem(subitem, "message");
            if (message)
            {
#ifdef TEMP_LOGGING
               logofs << prefix() << "message = " << message->valuestring << endl;
#endif
               RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"message = %s\n", message->valuestring);
            }
         }
         cJSON* statusCode = cJSON_GetObjectItem(response_json, "statusCode");
         if(statusCode)
         {
            ret = (WDMP_STATUS)statusCode->valueint;
#ifdef TEMP_LOGGING
            logofs << prefix() << "statusCode = " << ret << endl;
#endif
            RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"statusCode = %d\n", ret);
         }
      }
   }
   return ret;
}

WDMP_STATUS setRFCParameter(char *pcCallerID, const char* pcParameterName, const char* pcParameterValue, DATA_TYPE eDataType)
{
#ifdef TEMP_LOGGING 
   openLogFile();
#endif
   WDMP_STATUS ret = WDMP_FAILURE;
   long http_code = 0;
   string response;
   CURL *curl_handle = NULL;
   CURLcode res = CURLE_FAILED_INIT;

   if(!strcmp(pcParameterName+strlen(pcParameterName)-1,".") && pcParameterValue == NULL)
   {
#ifdef TEMP_LOGGING
   logofs << prefix() <<__FUNCTION__ << ": RFC API doesn't support wildcard parameterName or NULL parameterValue" << endl;
#endif
       RDK_LOG (RDK_LOG_DEBUG, LOG_RFCAPI, "%s: RFC API doesn't support wildcard parameterName or NULL parameterValue\n", __FUNCTION__);
       return ret;
   }

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
#ifdef TEMP_LOGGING
   logofs << prefix() << "setRFCParam data = " << data << " dataLen = " <<  data.length() << endl;
#endif
   RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"setRFCParam data = %s, datalen = %d\n", data.c_str(), data.length());

   if (curl_handle)
   {
       char pcCallerIDHeader[128];
       if(pcCallerID)
           sprintf(pcCallerIDHeader, "CallerID: %s", pcCallerID);
       else
           sprintf(pcCallerIDHeader, "CallerID: Unknown");

      struct curl_slist *customHeadersList = NULL;
      customHeadersList = curl_slist_append(customHeadersList, pcCallerIDHeader);
      curl_easy_setopt(curl_handle, CURLOPT_HTTPHEADER, customHeadersList);

      curl_easy_setopt(curl_handle, CURLOPT_URL, url);
      curl_easy_setopt(curl_handle, CURLOPT_HTTPPOST, 1L);
      curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDSIZE, (long) data.length());
      curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDS, data.c_str());
      curl_easy_setopt(curl_handle, CURLOPT_FOLLOWLOCATION, 1);
      curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, writeCurlResponse);
      curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, &response);

      res = curl_easy_perform(curl_handle);
      curl_easy_getinfo(curl_handle, CURLINFO_RESPONSE_CODE, &http_code);

#ifdef TEMP_LOGGING
   logofs << prefix() << "curl response = " << res << "http response code = " << http_code << endl;
#endif
      RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"curl response : %d http response code: %ld\n", res, http_code);
      curl_easy_cleanup(curl_handle);

      curl_slist_free_all(customHeadersList);
   }
   else
   {
#ifdef TEMP_LOGGING
   logofs << prefix() << "Could not perform curl" << endl;
#endif
      RDK_LOG(RDK_LOG_ERROR, LOG_RFCAPI,"Could not perform curl \n");
   }
   if (res == CURLE_OK)
   {
      cJSON *response_json = NULL;
#ifdef TEMP_LOGGING
   logofs << prefix() << "curl response: " << response << endl;
#endif
      RDK_LOG(RDK_LOG_DEBUG, LOG_RFCAPI,"Curl response: %s\n", response.c_str());
      response_json = cJSON_Parse(response.c_str());
      if (response_json)
      {
         cJSON* statusCode = cJSON_GetObjectItem(response_json, "statusCode");
         if(statusCode)
         {
            ret = (WDMP_STATUS)statusCode->valueint;
#ifdef TEMP_LOGGING
   logofs << prefix() << "statusCode = " << statusCode->valueint << endl;
#endif
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
