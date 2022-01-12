import { ContractReceipt, Event, Contract } from 'ethers'
import { Result } from 'ethers/lib/utils';

export const filterEvents = (
    blockEvents: ContractReceipt,
    name: String
  ): Array<Event> => {
    return blockEvents.events?.filter((event) => event.event === name) || [];
  };
  
  export const decodeEvents = <T extends Contract>(
    token: T,
    events: Array<Event>,
    filterByEventName?: string
  ): Array<Result> => {
    const decodedEvents = [];
    for (const event of events) {
      const getEventInterface = token.interface.getEvent(event.event || filterByEventName || "");
      try {
        getEventInterface && decodedEvents.push(
          token.interface.decodeEventLog(getEventInterface, event.data, event.topics)
        );
      } catch(e){
        
      }
    }
    return decodedEvents;
  };